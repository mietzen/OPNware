"""Unit and seam tests for os-logwatch plugin and backend core."""

import re
import sqlite3
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest
import yaml

ROOT_DIR = Path(__file__).resolve().parents[2]
PKG_DIR = ROOT_DIR / "pkgs" / "os-logwatch"
SRC_DIR = PKG_DIR / "src"
SCRIPTS_DIR = SRC_DIR / "opnsense" / "scripts" / "OPNsense" / "Logwatch"

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import logwatch_core as core  # noqa: E402
import manage as ly_manage  # noqa: E402


def test_package_structure_and_xml_valid():
    cfg = yaml.safe_load((PKG_DIR / "config.yml").read_text())
    assert cfg["pkg_manifest"]["name"] == "logwatch"
    assert cfg["pkg_manifest"]["origin"] == "opnware/os-logwatch"
    assert "monaco-editor" in cfg["pkg_manifest"]["deps"]
    assert (PKG_DIR / "build.sh").stat().st_mode & 0o111
    assert (SRC_DIR / "usr" / "local" / "etc" / "rc.d" / "logwatch").stat().st_mode & 0o111

    xml_files = [
        SRC_DIR / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Logwatch" / "Logwatch.xml",
        SRC_DIR / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Logwatch" / "Menu" / "Menu.xml",
        SRC_DIR / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Logwatch" / "ACL" / "ACL.xml",
        SRC_DIR / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Logwatch" / "forms" / "general.xml",
        SRC_DIR / "opnsense" / "www" / "js" / "widgets" / "Metadata" / "Logwatch.xml",
    ]
    for xf in xml_files:
        assert xf.exists(), f"Missing {xf}"
        ET.parse(xf)


def test_parse_raw_syslog_formats():
    r1 = core.parse_raw_syslog("<38>Nov 18 11:00:00 nas smbd[1234]: share mounted")
    assert r1["host"] == "nas"
    assert r1["facility"] == "auth"
    assert r1["severity"] == "info"
    assert r1["tag"] == "smbd"
    assert r1["message"] == "share mounted"

    r2 = core.parse_raw_syslog(
        "78 <131>1 2026-11-18T11:00:01+01:00 opnsense.internal unbound 999 - [meta seq=1] servfail example.com"
    )
    assert r2["host"] == "opnsense.internal"
    assert r2["facility"] == "local0"
    assert r2["severity"] == "err"
    assert r2["tag"] == "unbound"
    assert r2["message"] == "servfail example.com"

    r3 = core.parse_raw_syslog("unformatted plain line", peer="192.168.40.20")
    assert r3["host"] == "192.168.40.20"
    assert r3["severity"] == "info"
    assert r3["message"] == "unformatted plain line"


def test_validate_rules_and_full_config_paste():
    full_cfg = """
db_path: /etc/logwatch/logwatch.db
retention: 7
listen:
  udp: ":514"
alerts:
  - name: "Any Error"
    count: 1
    window_minutes: 5
    level: err
    above: true
ignore:
  - host: nas
    facility: daemon
    tag: smbd
    level: err
    discard: true
severity_rewrite:
  - host: docker-vm
    level: info
    message: "FATAL|ERROR"
    new_severity: err
digest:
  enabled: true
  initial: 5m
  multiplier: 3
  max: 2h
  cooldown: 10m
"""
    norm_yaml, parsed = core.validate_rules(full_cfg)
    assert "db_path" not in norm_yaml
    assert len(parsed["alerts"]) == 1
    assert parsed["ignore"][0]["discard"] is True
    assert parsed["severity_rewrite"][0]["new_severity"] == "err"
    assert parsed["digest"]["enabled"] is True

    with pytest.raises(ValueError, match="Invalid regex"):
        core.validate_rules("alerts:\n  - name: bad\n    count: 1\n    window_minutes: 5\n    level: err\n    message: '['\n")

    with pytest.raises(ValueError, match="multiplier"):
        core.validate_rules("digest:\n  multiplier: 1.1\n")


def test_discard_and_first_match_rewrite():
    _, parsed = core.validate_rules(
        """
ignore:
  - host: nas
    tag: "^smbd$"
    discard: true
  - host: nas
    message: "soft ignore"
    discard: false
severity_rewrite:
  - host: app1
    level: info
    message: "FATAL"
    new_severity: crit
  - host: app1
    level: info
    message: "FATAL|WARN"
    new_severity: warning
"""
    )
    compiled = core.compile_rules(parsed)

    assert core.should_discard(compiled, {"host": "nas", "tag": "smbd", "facility": "daemon", "severity": "err", "message": "x"})
    assert not core.should_discard(compiled, {"host": "nas", "tag": "sshd", "facility": "auth", "severity": "info", "message": "soft ignore"})

    rewritten = core.apply_rewrite(compiled, {"host": "app1", "tag": "api", "facility": "user", "severity": "info", "message": "FATAL crash"})
    assert rewritten == "crit"


def test_sqlite_query_filters_alerts_and_retention(tmp_path):
    db_file = str(tmp_path / "logwatch.db")
    conn = core.open_db(db_file)
    now = int(time.time())

    core.insert_logs(conn, [
        {"timestamp": "2026-11-18 10:00:00", "epoch": now - 120, "host": "nas", "facility": "daemon", "severity": "err", "tag": "smbd", "message": "disk error 42"},
        {"timestamp": "2026-11-18 10:01:00", "epoch": now - 60, "host": "nas", "facility": "daemon", "severity": "warning", "tag": "smbd", "message": "noisy ignore me"},
        {"timestamp": "2026-11-18 10:02:00", "epoch": now - 30, "host": "router", "facility": "kern", "severity": "crit", "tag": "kernel", "message": "link down igc0"},
        {"timestamp": "2026-11-01 10:00:00", "epoch": now - 20 * 86400, "host": "old", "facility": "user", "severity": "info", "tag": "cron", "message": "ancient"},
    ])

    # Severity >= err should include err and crit
    res = core.query_logs(conn, {"severity": "err"})
    assert res["total"] == 2
    assert {r["host"] for r in res["rows"]} == {"nas", "router"}

    # Regex search
    rx_res = core.query_logs(conn, {"search": r"error \d+$", "search_mode": core.SearchMode.REGEX})
    assert rx_res["total"] == 1
    assert rx_res["rows"][0]["host"] == "nas"

    # Cross-filtered dropdowns
    flt = core.get_filters(conn, {"host": "router"})
    assert flt["tag"] == ["kernel"]
    assert "router" in flt["host"]

    # Alert evaluation excluding ignore rules
    _, parsed = core.validate_rules(
        """
alerts:
  - name: "Crit or Err"
    count: 2
    window_minutes: 10
    level: err
    above: true
ignore:
  - host: nas
    message: "noisy ignore"
    discard: false
"""
    )
    compiled = core.compile_rules(parsed)
    cnt, samples = core.eval_alert_rule(conn, compiled["alerts"][0], compiled["ignore"], now_epoch=now)
    assert cnt == 2
    assert len(samples) == 2

    core.mark_alerted(conn, "Crit or Err", cnt, now_epoch=now)
    cnt_cooldown, _ = core.eval_alert_rule(conn, compiled["alerts"][0], compiled["ignore"], now_epoch=now + 10)
    assert cnt_cooldown == 0

    # Retention deletes 20-day-old row
    deleted = core.prune_logs(conn, db_file, retention_days=7, max_db_size_mb=512, now_epoch=now)
    assert deleted == 1
    conn.close()


def test_load_config_reuses_monit_smtp(tmp_path):
    xml_path = tmp_path / "config.xml"
    xml_path.write_text(
        """<opnsense>
  <system><hostname>fw01</hostname><domain>internal</domain></system>
  <OPNsense>
    <monit>
      <general>
        <mailserver>smtp.mailbox.org</mailserver>
        <port>587</port>
        <username>user@example.org</username>
        <password>secret</password>
        <ssl>1</ssl>
        <sslverify>1</sslverify>
      </general>
      <alert>
        <enabled>1</enabled>
        <recipient>ops@example.org</recipient>
        <format>From: OPNsense &lt;noreply@example.org&gt;
Subject: Alert</format>
      </alert>
    </monit>
    <logwatch>
      <general>
        <enabled>1</enabled>
        <use_monit_smtp>1</use_monit_smtp>
      </general>
    </logwatch>
  </OPNsense>
</opnsense>"""
    )
    cfg = core.load_config(str(xml_path))
    assert cfg.hostname == "fw01.internal"
    assert cfg.smtp.host == "smtp.mailbox.org"
    assert cfg.smtp.port == 587
    assert cfg.smtp.from_addr == "noreply@example.org"
    assert cfg.smtp.to_addr == "ops@example.org"
    assert cfg.smtp.source == "monit"


def test_syslog_ng_conf_has_unique_persist_names(monkeypatch):
    cfg = core.PluginConfig(enabled=True, listen_interfaces=["lan", "opt1"], enable_udp=True, enable_tcp=True)
    monkeypatch.setattr(ly_manage, "_resolve_iface_ips", lambda _ifaces: ["192.168.40.1", "10.0.0.1"])
    monkeypatch.setattr(ly_manage, "_discover_plugin_modules", lambda: [])
    text = ly_manage._build_syslog_ng_conf(cfg)
    assert 'persist-name("logwatch_remote")' in text
    assert 'persist-name("logwatch_local")' in text
    assert 'persist-name("logwatch_net_udp_0")' in text
    assert 'persist-name("logwatch_net_tcp_1")' in text


def test_prune_logs_zero_deleted_does_not_lock_db(tmp_path):
    db_file = str(tmp_path / "logwatch.db")
    conn_ticker = core.open_db(db_file)
    conn_writer = sqlite3.connect(db_file, timeout=0.1)
    now = int(time.time())

    try:
        core.insert_logs(conn_writer, [{
            "timestamp": "2026-11-18 13:00:00",
            "epoch": now,
            "host": "fw01",
            "facility": "user",
            "severity": "info",
            "tag": "test",
            "message": "fresh entry",
        }])

        deleted = core.prune_logs(conn_ticker, db_file, retention_days=7, max_db_size_mb=512, now_epoch=now)
        assert deleted == 0
        assert not conn_ticker.in_transaction

        core.insert_logs(conn_writer, [{
            "timestamp": "2026-11-18 13:00:05",
            "epoch": now + 5,
            "host": "fw01",
            "facility": "user",
            "severity": "info",
            "tag": "test",
            "message": "second entry",
        }])
    finally:
        conn_writer.close()
        conn_ticker.close()


def test_logwatch_daemon_syslog_conf_matches_bracketed_levels():
    conf_path = SRC_DIR / "etc" / "syslog-ng.conf.d" / "logwatch-daemon.conf"
    conf = conf_path.read_text()

    assert ".*error.*" not in conf
    assert ".*warn.*" not in conf
    assert r'\\[error\\]' in conf
    assert r'\\[warn\\]' in conf

    patterns = [m.replace(r"\\", "\\") for m in re.findall(r'message\("([^"]+)"\)', conf)]
    assert len(patterns) >= 3
    err_rx, warn_rx, info_neg_rx = patterns[0], patterns[1], patterns[2]

    info_msg = "2026-11-18 13:40:03 [info] Sent alert email for 'Any Error or above' (3 hits)"
    info_warn_msg = "2026-11-18 13:40:03 [info] Sent alert email for 'Many warnings' (10 hits)"
    warn_msg = "2026-11-18 13:40:03 [warn] Ingest queue full, dropping log entry"
    err_msg = "2026-11-18 13:40:03 [error] Alert evaluation error"
    tb_msg = "Traceback (most recent call last):"

    assert not re.search(err_rx, info_msg)
    assert not re.search(warn_rx, info_warn_msg)
    assert not re.search(info_neg_rx, info_msg)
    assert not re.search(info_neg_rx, info_warn_msg)
    assert re.search(warn_rx, warn_msg)
    assert re.search(err_rx, err_msg)
    assert re.search(err_rx, tb_msg)
