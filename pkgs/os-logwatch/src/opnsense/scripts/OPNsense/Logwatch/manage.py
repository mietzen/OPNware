#!/usr/local/bin/python3
"""CLI management helper invoked by configd actions for os-logwatch."""

import glob
import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import yaml

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import logwatch_core as core

RE_MOD_LOGDIR = re.compile(r"/var/log/([a-zA-Z0-9_-]+)/\1_")

# Command currently being executed; stamped into every emitted payload so the
# PHP side can reject stale manage_status.json content from other commands.
_CURRENT_CMD = ""
# Nonce embedded by the PHP controller into the staged request file; echoed
# back in every response payload so runAction can match request <-> response.
_CURRENT_REQUEST_ID = None


def _emit(payload, cmd=None):
    payload = dict(payload)
    payload["cmd"] = cmd if cmd is not None else _CURRENT_CMD
    if _CURRENT_REQUEST_ID is not None:
        payload["request_id"] = _CURRENT_REQUEST_ID
    os.makedirs(core.STATE_DIR, mode=0o755, exist_ok=True)
    tmp = f"{core.STATUS_FILE}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh)
    os.chmod(tmp, 0o600)
    os.replace(tmp, core.STATUS_FILE)
    print(json.dumps(payload))


def _load_request(cmd, arg=None):
    """Read the staged per-command request JSON payload.

    The CLI argv slot is kept for compatibility but intentionally ignored:
    payloads travel via staged files so configd's 4KB socket message limit can
    never truncate them and secrets never reach configd params/logs.
    Returns the payload dict, or None after emitting status:error.
    """
    global _CURRENT_REQUEST_ID
    try:
        path = core.request_path(cmd)
    except ValueError as exc:
        _emit({"status": "error", "message": str(exc)}, cmd)
        return None

    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        _emit({"status": "error", "message": f"Missing or unreadable staged request for '{cmd}': {exc}"}, cmd)
        return None

    # The staged request is consumed exactly once by this invocation; remove it
    # best-effort so secrets (e.g. SMTP credentials) do not persist at rest.
    try:
        os.unlink(path)
    except OSError:
        pass

    if not isinstance(data, dict):
        _emit({"status": "error", "message": f"Invalid staged request payload for '{cmd}'"}, cmd)
        return None

    req_id = data.get("request_id")
    if isinstance(req_id, str) and req_id:
        _CURRENT_REQUEST_ID = req_id

    return data


def _cmd_query(arg):
    params = _load_request("query", arg)
    if params is None:
        return
    if params.get("regex"):
        params["search_mode"] = core.SearchMode.REGEX
    else:
        params["search_mode"] = core.SearchMode.SUBSTRING

    cfg = core.load_config()
    conn = core.open_db()
    try:
        res = core.query_logs(conn, params)
    finally:
        conn.close()

    alerts_clean = [
        {k: v for k, v in r.items() if not k.startswith("_")}
        for r in cfg.rules.get("alerts", [])
    ]
    res["status"] = "ok"
    res["alert_rules"] = alerts_clean
    res["db_size_bytes"] = os.path.getsize(core.DB_PATH) if os.path.exists(core.DB_PATH) else 0
    _emit(res)


def _cmd_filters(arg):
    params = _load_request("filters", arg)
    if params is None:
        return
    conn = core.open_db()
    try:
        filters = core.get_filters(conn, params)
        total = int(conn.execute("SELECT COUNT(*) FROM logs").fetchone()[0])
    finally:
        conn.close()

    db_bytes = os.path.getsize(core.DB_PATH) if os.path.exists(core.DB_PATH) else 0
    _emit({
        "status": "ok",
        "hosts": filters["host"],
        "facilities": filters["facility"],
        "severities": filters["severity"],
        "tags": filters["tag"],
        "total_rows": total,
        "db_size_bytes": db_bytes,
    })


def _cmd_stats():
    now = int(time.time())
    h1 = now - 3600
    h24 = now - 86400
    conn = core.open_db()
    try:
        total = int(conn.execute("SELECT COUNT(*) FROM logs").fetchone()[0])
        err_sevs = ("emerg", "alert", "crit", "err")
        marks = ",".join("?" for _ in err_sevs)
        e1 = int(conn.execute(f"SELECT COUNT(*) FROM logs WHERE epoch >= ? AND severity IN ({marks})", (h1, *err_sevs)).fetchone()[0])
        e24 = int(conn.execute(f"SELECT COUNT(*) FROM logs WHERE epoch >= ? AND severity IN ({marks})", (h24, *err_sevs)).fetchone()[0])
        w1 = int(conn.execute("SELECT COUNT(*) FROM logs WHERE epoch >= ? AND severity = 'warning'", (h1,)).fetchone()[0])
        w24 = int(conn.execute("SELECT COUNT(*) FROM logs WHERE epoch >= ? AND severity = 'warning'", (h24,)).fetchone()[0])
        alerts = [
            dict(r)
            for r in conn.execute(
                "SELECT rule_name, last_alerted_at, last_count FROM alert_state ORDER BY last_alerted_at DESC LIMIT 5"
            ).fetchall()
        ]
    finally:
        conn.close()

    db_bytes = os.path.getsize(core.DB_PATH) if os.path.exists(core.DB_PATH) else 0
    _emit({
        "status": "ok",
        "total_rows": total,
        "db_size_mb": round(db_bytes / (1024 * 1024), 2),
        "errors_1h": e1,
        "warnings_1h": w1,
        "errors_24h": e24,
        "warnings_24h": w24,
        "recent_alerts": alerts,
    })


def _cmd_rules_validate():
    if not os.path.exists(core.STAGED_RULES_FILE):
        _emit({"status": "error", "message": "No staged rules found"})
        return

    with open(core.STAGED_RULES_FILE, "r", encoding="utf-8") as fh:
        raw = fh.read()

    norm_yaml, parsed = core.validate_rules(raw)
    _emit({"status": "ok", "yaml": norm_yaml, "parsed": parsed})


def _cmd_add_ignore(arg):
    payload = _load_request("add-ignore", arg)
    if payload is None:
        return
    raw_yaml = payload.get("yaml") or core.DEFAULT_RULES_YAML
    new_rule = payload.get("rule") or {}

    _, parsed = core.validate_rules(raw_yaml)
    clean_rule = {}
    for key in ("host", "facility", "tag", "level", "message"):
        val = str(new_rule.get(key) or "").strip()
        if val:
            clean_rule[key] = val.lower() if key == "level" else val
    clean_rule["discard"] = bool(new_rule.get("discard", False))

    if clean_rule not in parsed["ignore"]:
        parsed["ignore"].append(clean_rule)

    new_yaml = yaml.safe_dump(parsed, sort_keys=False, default_flow_style=False)
    norm_yaml, validated = core.validate_rules(new_yaml)
    _emit({"status": "ok", "yaml": norm_yaml, "parsed": validated})


def _cmd_alert_state():
    cfg = core.load_config()
    conn = core.open_db()
    try:
        rows = {
            r["rule_name"]: dict(r)
            for r in conn.execute("SELECT rule_name, last_alerted_at, last_count FROM alert_state").fetchall()
        }
        q_cnt = int(conn.execute("SELECT COUNT(*) FROM digest_queue").fetchone()[0])
        meta = {
            r["key"]: r["value"]
            for r in conn.execute("SELECT key, value FROM digest_meta").fetchall()
        }
    finally:
        conn.close()

    rules_state = []
    for r in cfg.rules.get("alerts", []):
        st = rows.get(r["name"], {})
        rules_state.append({
            "name": r["name"],
            "last_alerted_at": int(st.get("last_alerted_at", 0)),
            "last_count": int(st.get("last_count", 0)),
        })

    _emit({
        "status": "ok",
        "rules": rules_state,
        "digest": {
            "queued_count": q_cnt,
            "window_sec": int(meta.get("window_sec", 0)),
            "next_flush": int(meta.get("next_flush", 0)),
            "last_sent": int(meta.get("last_digest_sent", 0)),
        },
    })


def _cmd_reset_cooldown(arg):
    payload = _load_request("reset-cooldown", arg)
    if payload is None:
        return
    rule_name = str(payload.get("rule_name") or "").strip()
    clear_digest = bool(payload.get("clear_digest", False))
    conn = core.open_db()
    try:
        if clear_digest:
            conn.execute("DELETE FROM digest_queue")
            conn.execute("DELETE FROM digest_meta")
        if rule_name:
            conn.execute("DELETE FROM alert_state WHERE rule_name = ?", (rule_name,))
        elif not clear_digest:
            conn.execute("DELETE FROM alert_state")
        conn.commit()
    finally:
        conn.close()

    _emit({"status": "ok", "message": "Cooldown state reset"})


def _cmd_test_smtp(arg):
    payload = _load_request("test-smtp", arg)
    if payload is None:
        return
    cfg = core.load_config()

    # Allow testing unsaved SMTP edits directly from the UI Settings form
    if "use_monit_smtp" in payload:
        if not payload["use_monit_smtp"]:
            cfg.smtp = core.SmtpConfig(
                host=str(payload.get("smtp_host") or "").strip(),
                port=int(payload.get("smtp_port") or core.DEFAULT_SMTP_PORT),
                user=str(payload.get("smtp_user") or "").strip(),
                password=str(payload.get("smtp_password") or "").strip(),
                from_addr=str(payload.get("smtp_from") or "").strip(),
                to_addr=str(payload.get("smtp_to") or "").strip(),
                use_ssl=True,
                ssl_verify=False,
                source="custom",
            )
        else:
            for k, attr in (
                ("smtp_host", "host"),
                ("smtp_user", "user"),
                ("smtp_password", "password"),
                ("smtp_from", "from_addr"),
                ("smtp_to", "to_addr"),
            ):
                val = str(payload.get(k) or "").strip()
                if val:
                    setattr(cfg.smtp, attr, val)
            if payload.get("smtp_port"):
                port_val = int(payload["smtp_port"])
                if port_val != core.DEFAULT_SMTP_PORT or str(payload.get("smtp_host") or "").strip():
                    cfg.smtp.port = port_val

    html = core.build_alert_html(
        "Logwatch Test Email",
        [{
            "heading": "SMTP Delivery Check",
            "summary": f"Test notification sent from {cfg.hostname} via {cfg.smtp.source} SMTP ({cfg.smtp.host}:{cfg.smtp.port}).",
            "samples": [],
        }],
        core.ui_footer_url(cfg),
    )
    core.send_email(cfg.smtp, f"[Logwatch] Test Email from {cfg.hostname}", html)
    _emit({"status": "ok", "message": f"Test email sent to {cfg.smtp.to_addr} via {cfg.smtp.host}:{cfg.smtp.port}"})


def _cmd_clear_logs():
    conn = core.open_db()
    try:
        conn.execute("DELETE FROM logs")
        conn.execute("DELETE FROM digest_queue")
        conn.commit()
        conn.execute("VACUUM")
    finally:
        conn.close()

    _emit({"status": "ok", "message": "All stored logs cleared"})


def _resolve_iface_ips(iface_keys):
    """Resolve OPNsense interface names (lan, opt1, ...) to concrete local IPs."""
    ips = []
    if not os.path.exists(core.CONFIG_XML_PATH):
        return ["127.0.0.1"]

    root = ET.parse(core.CONFIG_XML_PATH).getroot()
    for key in iface_keys:
        if_el = root.find(f"interfaces/{key}")
        if if_el is None:
            continue
        dev = (if_el.findtext("if") or "").strip()
        static_ip = (if_el.findtext("ipaddr") or "").strip()

        found_dev_ips = []
        if dev:
            out = subprocess.run(["/sbin/ifconfig", dev], capture_output=True, text=True)
            if out.returncode == 0:
                for line in out.stdout.splitlines():
                    line = line.strip()
                    if line.startswith("inet "):
                        ip = line.split()[1]
                        if ip not in found_dev_ips:
                            found_dev_ips.append(ip)
                    elif line.startswith("inet6 "):
                        ip6 = line.split()[1].split("%")[0]
                        if not ip6.lower().startswith("fe80:") and ip6 not in found_dev_ips:
                            found_dev_ips.append(ip6)

        if not found_dev_ips and static_ip and static_ip not in ("dhcp", "none"):
            found_dev_ips.append(static_ip)

        for ip in found_dev_ips:
            if ip not in ips:
                ips.append(ip)

    return ips or ["127.0.0.1"]


def _discover_plugin_modules():
    """Find OPNware plugin syslog directories from /usr/local/etc/syslog-ng.conf.d/*.conf."""
    mods = []
    for path in sorted(glob.glob(f"{core.SYSLOG_NG_CONF_D}/*.conf")):
        base = os.path.basename(path)
        if base.startswith("syslog-ng-") or base.startswith("logwatch"):
            continue
        try:
            content = open(path, "r", encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for match in RE_MOD_LOGDIR.finditer(content):
            mod = match.group(1)
            if mod != "logwatch" and mod not in mods and os.path.isdir(f"/var/log/{mod}"):
                mods.append(mod)
    return mods


def _build_syslog_ng_conf(cfg):
    if not cfg.enabled:
        return "# os-logwatch is disabled — no ingestion rules active.\n"

    lines = [
        "# Auto-generated by os-logwatch setup. Do not edit manually.",
        "",
        "destination d_logwatch_remote {",
        # time-reopen(1): after a daemon restart the socket inode is replaced; reconnect
        # fast so syslog-ng does not keep writing to the dead fd (ECONNRESET spam)
        f'    unix-dgram("{core.INGEST_SOCK}" persist-name("logwatch_remote") time-reopen(1) log-fifo-size(10000)',
        '        template("$(format-json ts=$ISODATE peer=$SOURCEIP raw=$MESSAGE source=remote)\\n"));',
        "};",
        "",
        "destination d_logwatch_local {",
        f'    unix-dgram("{core.INGEST_SOCK}" persist-name("logwatch_local") time-reopen(1) log-fifo-size(10000)',
        '        template("$(format-json ts=$ISODATE host=$HOST facility=$FACILITY severity=$LEVEL tag=$PROGRAM msg=$MESSAGE source=local)\\n"));',
        "};",
        "",
    ]

    if cfg.enable_udp or cfg.enable_tcp:
        ips = _resolve_iface_ips(cfg.listen_interfaces)
        lines.append("source s_logwatch_net {")
        for idx, ip in enumerate(ips):
            ip_ver = 6 if ":" in ip else 4
            if cfg.enable_udp:
                lines.append(
                    f'    network(ip("{ip}") port({cfg.listen_port}) transport("udp") ip-protocol({ip_ver}) '
                    f'flags(no-parse) persist-name("logwatch_net_udp_{idx}"));'
                )
            if cfg.enable_tcp:
                lines.append(
                    f'    network(ip("{ip}") port({cfg.listen_port}) transport("tcp") ip-protocol({ip_ver}) '
                    f'flags(no-parse) persist-name("logwatch_net_tcp_{idx}"));'
                )
        lines.append("};")
        lines.append("")
        lines.append("log { source(s_logwatch_net); destination(d_logwatch_remote); };")
        lines.append("")

    if cfg.capture_local:
        # Guard against feedback loop if ingest socket temporarily closes
        lines.extend([
            "filter f_logwatch_not_self {",
            '    not message("os-logwatch/ingest.sock");',
            "};",
            "",
            "log {",
            "    source(s_all);",
            "    filter(f_logwatch_not_self);",
            "    destination(d_logwatch_local);",
            "};",
            "",
        ])

        for mod in _discover_plugin_modules():
            src_name = f"s_logwatch_mod_{mod.replace('-', '_')}"
            lines.extend([
                f"source {src_name} {{",
                "    wildcard-file(",
                f'        base-dir("/var/log/{mod}")',
                f'        filename-pattern("{mod}_*.log")',
                "        flags(syslog-protocol)",
                "        follow-freq(1)",
                "    );",
                "};",
                f"log {{ source({src_name}); destination(d_logwatch_local); }};",
                "",
            ])

    return "\n".join(lines)


def _cmd_setup(no_reload=False):
    os.makedirs(core.STATE_DIR, mode=0o755, exist_ok=True)
    os.makedirs(core.RUN_DIR, mode=0o755, exist_ok=True)
    os.makedirs(core.LOG_DIR, mode=0o755, exist_ok=True)

    # Ensure DB schema exists on fresh install
    conn = core.open_db()
    conn.close()

    cfg = core.load_config()
    conf_text = _build_syslog_ng_conf(cfg)

    old_text = ""
    if os.path.exists(core.SYSLOG_NG_INGEST_CONF):
        old_text = open(core.SYSLOG_NG_INGEST_CONF, "r", encoding="utf-8").read()

    dirty_marker = f"{core.STATE_DIR}/.syslog_dirty"
    changed = (conf_text != old_text)
    if changed:
        tmp = f"{core.SYSLOG_NG_INGEST_CONF}.tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(conf_text)
        os.chmod(tmp, 0o644)
        os.replace(tmp, core.SYSLOG_NG_INGEST_CONF)

        check = subprocess.run(["/usr/local/sbin/syslog-ng", "-s"], capture_output=True, text=True)
        if check.returncode != 0:
            # Roll back immediately so OPNsense syslog-ng never stays broken
            with open(core.SYSLOG_NG_INGEST_CONF, "w", encoding="utf-8") as fh:
                fh.write(old_text)
            raise RuntimeError(f"syslog-ng validation failed: {check.stderr or check.stdout}")

        with open(dirty_marker, "w", encoding="utf-8") as fh:
            fh.write("1")

    if not no_reload and (changed or os.path.exists(dirty_marker)):
        # pluginctl masks syslog-ng-ctl reload failures with exit 0; invoke syslog-ng-ctl directly
        res = subprocess.run(["/usr/local/sbin/syslog-ng-ctl", "reload"], capture_output=True, text=True)
        if res.returncode != 0:
            subprocess.run(["/usr/sbin/service", "syslog-ng", "onerestart"], capture_output=True, text=True)
        if os.path.exists(dirty_marker):
            os.unlink(dirty_marker)

    _emit({"status": "ok", "syslog_ng_updated": changed, "enabled": cfg.enabled})


def main():
    global _CURRENT_CMD, _CURRENT_REQUEST_ID
    if len(sys.argv) < 2:
        _emit({"status": "error", "message": "Missing command"})
        return

    cmd = sys.argv[1]
    _CURRENT_CMD = cmd
    _CURRENT_REQUEST_ID = None
    arg = sys.argv[2] if len(sys.argv) > 2 else ""

    try:
        if cmd == "query":
            _cmd_query(arg)
        elif cmd == "filters":
            _cmd_filters(arg)
        elif cmd == "stats":
            _cmd_stats()
        elif cmd == "rules-validate":
            _cmd_rules_validate()
        elif cmd == "add-ignore":
            _cmd_add_ignore(arg)
        elif cmd == "alert-state":
            _cmd_alert_state()
        elif cmd == "reset-cooldown":
            _cmd_reset_cooldown(arg)
        elif cmd == "test-smtp":
            _cmd_test_smtp(arg)
        elif cmd == "clear-logs":
            _cmd_clear_logs()
        elif cmd == "setup":
            _cmd_setup(no_reload=("--no-reload" in sys.argv[2:]))
        else:
            _emit({"status": "error", "message": f"Unknown command: {cmd}"})
    except Exception as exc:
        _emit({"status": "error", "message": str(exc)}, cmd)


if __name__ == "__main__":
    main()
