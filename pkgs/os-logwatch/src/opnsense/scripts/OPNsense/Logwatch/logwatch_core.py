#!/usr/local/bin/python3
"""Core domain logic for os-logwatch: parsing, rules, SQLite, and SMTP."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from enum import Enum
from functools import lru_cache
import os
import re
import smtplib
import sqlite3
import ssl
import time
import xml.etree.ElementTree as ET
import yaml

# Filesystem & runtime constants
CONFIG_XML_PATH = "/conf/config.xml"
STATE_DIR = "/var/db/os-logwatch"
RUN_DIR = "/var/run/os-logwatch"
LOG_DIR = "/var/log/logwatch"
DB_PATH = f"{STATE_DIR}/logwatch.db"
STATUS_FILE = f"{STATE_DIR}/manage_status.json"
STAGED_RULES_FILE = f"{STATE_DIR}/staged_rules.yml"
SEEDED_MARKER = f"{STATE_DIR}/.seeded"
INGEST_SOCK = f"{RUN_DIR}/ingest.sock"
PID_FILE = f"{RUN_DIR}/logwatch.pid"
SYSLOG_NG_CONF_D = "/usr/local/etc/syslog-ng.conf.d"
SYSLOG_NG_INGEST_CONF = f"{SYSLOG_NG_CONF_D}/logwatch-ingest.conf"

DEFAULT_PORT = 514
DEFAULT_RETENTION_DAYS = 7
DEFAULT_MAX_DB_MB = 512
DEFAULT_SMTP_PORT = 587
SMTPS_PORT = 465
ALERT_SAMPLE_LIMIT = 50
DEFAULT_QUERY_LIMIT = 200
PRUNE_BATCH_PCT = 10

SEVERITY_ORDER = (
    "emerg",
    "alert",
    "crit",
    "err",
    "warning",
    "notice",
    "info",
    "debug",
)

SEVERITY_ALIASES = {
    "0": "emerg",
    "emergency": "emerg",
    "panic": "emerg",
    "1": "alert",
    "2": "crit",
    "critical": "crit",
    "3": "err",
    "error": "err",
    "4": "warning",
    "warn": "warning",
    "5": "notice",
    "6": "info",
    "informational": "info",
    "7": "debug",
}

FACILITY_NAMES = (
    "kern", "user", "mail", "daemon", "auth", "syslog", "lpr", "news",
    "uucp", "cron", "authpriv", "ftp", "ntp", "audit", "alert", "clock",
    "local0", "local1", "local2", "local3", "local4", "local5", "local6", "local7",
)

DEFAULT_RULES_YAML = """alerts:
  - name: "Many warnings"
    count: 10
    window_minutes: 5
    level: warning
    above: false
  - name: "Any Error or above"
    count: 1
    window_minutes: 5
    level: err
    above: true
ignore: []
severity_rewrite: []
digest:
  enabled: false
  initial: 5m
  multiplier: 3
  max: 2h
  cooldown: 10m
"""

DEFAULT_DIGEST_CFG = {
    "enabled": False,
    "initial": "5m",
    "multiplier": 3.0,
    "max": "2h",
    "cooldown": "10m",
}

# Precompiled syslog wire patterns (RFC5424 & RFC3164)
RE_OCTET_FRAME = re.compile(r"^\d+\s+(?=<)")
RE_RFC5424 = re.compile(
    r"^<(\d{1,3})>1\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(?:\[.*?\]|-)\s*(.*)$"
)
RE_RFC3164_ISO = re.compile(
    r"^<(\d{1,3})>(\d{4}-\d{2}-\d{2}T\S+)\s+(\S+)\s+([^\s:\[]+)(?:\[\d+\])?:\s*(.*)$"
)
RE_RFC3164_BSD = re.compile(
    r"^<(\d{1,3})>([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+([^\s:\[]+)(?:\[\d+\])?:\s*(.*)$"
)
RE_RFC3164_NOTAG = re.compile(
    r"^<(\d{1,3})>([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(.*)$"
)
RE_PRI_ONLY = re.compile(r"^<(\d{1,3})>(.*)$")
RE_DURATION = re.compile(r"^(\d+(?:\.\d+)?)\s*(s|m|h|d)$", re.IGNORECASE)
DURATION_UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400}


class SearchMode(Enum):
    SUBSTRING = "substring"
    REGEX = "regex"


class RuleTarget(Enum):
    DISCARD = "discard"
    REWRITE = "rewrite"
    ALERT = "alert"


@dataclass
class SmtpConfig:
    host: str = ""
    port: int = DEFAULT_SMTP_PORT
    user: str = ""
    password: str = ""
    from_addr: str = ""
    to_addr: str = ""
    use_ssl: bool = True
    ssl_verify: bool = False
    source: str = "none"


@dataclass
class PluginConfig:
    enabled: bool = True
    listen_interfaces: list = field(default_factory=lambda: ["lan"])
    listen_port: int = DEFAULT_PORT
    enable_udp: bool = True
    enable_tcp: bool = True
    auto_firewall: bool = True
    capture_local: bool = True
    excluded_programs: set = field(default_factory=lambda: {"filterlog"})
    min_local_severity: str = "info"
    retention_days: int = DEFAULT_RETENTION_DAYS
    max_db_size_mb: int = DEFAULT_MAX_DB_MB
    external_url: str = ""
    hostname: str = "opnsense"
    smtp: SmtpConfig = field(default_factory=SmtpConfig)
    rules_yaml: str = DEFAULT_RULES_YAML
    rules: dict = field(default_factory=dict)


def norm_sev(val):
    """Normalize any syslog severity token to canonical RFC5424 name."""
    if val is None:
        return "info"

    s = str(val).strip().lower()
    if s in SEVERITY_ORDER:
        return s

    if s in SEVERITY_ALIASES:
        return SEVERITY_ALIASES[s]

    return "info"


def sev_at_or_above(level):
    """Return list of severities equal to or more critical than level."""
    lvl = norm_sev(level)
    idx = SEVERITY_ORDER.index(lvl)
    return list(SEVERITY_ORDER[: idx + 1])


def pri_to_fac_sev(pri):
    """Split numeric RFC syslog PRI into (facility, severity)."""
    fac_num = pri // 8
    sev_num = pri % 8
    fac = FACILITY_NAMES[fac_num] if 0 <= fac_num < len(FACILITY_NAMES) else f"facility{fac_num}"
    sev = SEVERITY_ORDER[sev_num] if 0 <= sev_num < len(SEVERITY_ORDER) else f"severity{sev_num}"
    return fac, sev


def parse_dur(raw):
    """Parse duration string like '5m' or '2h' into seconds."""
    if isinstance(raw, (int, float)):
        return max(1, int(raw))

    txt = str(raw or "").strip()
    m = RE_DURATION.match(txt)
    if not m:
        raise ValueError(f"Invalid duration '{txt}' (expected e.g. 30s, 5m, 2h, 1d)")

    val = float(m.group(1))
    unit = DURATION_UNITS[m.group(2).lower()]
    secs = int(val * unit)
    if secs < 1:
        raise ValueError(f"Duration '{txt}' must be at least 1s")

    return secs


def parse_ts(raw_ts, fallback_epoch=None):
    """Parse ISO or BSD syslog timestamp to (epoch_int, display_iso_str)."""
    now = int(fallback_epoch if fallback_epoch is not None else time.time())
    if not raw_ts or raw_ts == "-":
        dt = datetime.fromtimestamp(now).astimezone()
        return int(dt.timestamp()), dt.strftime("%Y-%m-%d %H:%M:%S")

    txt = str(raw_ts).strip()
    try:
        iso_norm = txt[:-1] + "+00:00" if txt.endswith("Z") else txt
        dt = datetime.fromisoformat(iso_norm)
        if dt.tzinfo is None:
            dt = dt.astimezone()
        return int(dt.timestamp()), dt.astimezone().strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        pass

    # Handle RFC3164 BSD timestamp: "Nov 18 11:00:00"
    cleaned = re.sub(r"\s+", " ", txt)
    try:
        cur_year = datetime.now().year
        parsed = datetime.strptime(f"{cur_year} {cleaned}", "%Y %b %d %H:%M:%S")
        now_dt = datetime.now()
        if parsed.month == 12 and now_dt.month == 1:
            parsed = parsed.replace(year=cur_year - 1)
        dt = parsed.astimezone()
        return int(dt.timestamp()), dt.strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        dt = datetime.fromtimestamp(now).astimezone()
        return int(dt.timestamp()), dt.strftime("%Y-%m-%d %H:%M:%S")


def parse_raw_syslog(raw, peer="", fallback_ts=""):
    """Parse raw RFC3164 or RFC5424 line into normalized log dict."""
    line = RE_OCTET_FRAME.sub("", (raw or "").strip())
    fallback_epoch, _ = parse_ts(fallback_ts)

    m = RE_RFC5424.match(line)
    if m:
        fac, sev = pri_to_fac_sev(int(m.group(1)))
        epoch, ts_str = parse_ts(m.group(2), fallback_epoch)
        host = m.group(3) if m.group(3) != "-" else peer
        tag = "" if m.group(4) == "-" else m.group(4)
        return {
            "epoch": epoch,
            "timestamp": ts_str,
            "host": host or peer or "unknown",
            "facility": fac,
            "severity": sev,
            "tag": tag,
            "message": m.group(7),
        }

    m = RE_RFC3164_ISO.match(line)
    if m:
        fac, sev = pri_to_fac_sev(int(m.group(1)))
        epoch, ts_str = parse_ts(m.group(2), fallback_epoch)
        return {
            "epoch": epoch,
            "timestamp": ts_str,
            "host": m.group(3) or peer or "unknown",
            "facility": fac,
            "severity": sev,
            "tag": m.group(4),
            "message": m.group(5),
        }

    m = RE_RFC3164_BSD.match(line)
    if m:
        fac, sev = pri_to_fac_sev(int(m.group(1)))
        epoch, ts_str = parse_ts(m.group(2), fallback_epoch)
        return {
            "epoch": epoch,
            "timestamp": ts_str,
            "host": m.group(3) or peer or "unknown",
            "facility": fac,
            "severity": sev,
            "tag": m.group(4),
            "message": m.group(5),
        }

    m = RE_RFC3164_NOTAG.match(line)
    if m:
        fac, sev = pri_to_fac_sev(int(m.group(1)))
        epoch, ts_str = parse_ts(m.group(2), fallback_epoch)
        return {
            "epoch": epoch,
            "timestamp": ts_str,
            "host": m.group(3) or peer or "unknown",
            "facility": fac,
            "severity": sev,
            "tag": "",
            "message": m.group(4),
        }

    m = RE_PRI_ONLY.match(line)
    if m:
        fac, sev = pri_to_fac_sev(int(m.group(1)))
        epoch, ts_str = parse_ts(fallback_ts, fallback_epoch)
        return {
            "epoch": epoch,
            "timestamp": ts_str,
            "host": peer or "unknown",
            "facility": fac,
            "severity": sev,
            "tag": "",
            "message": m.group(2).strip(),
        }

    epoch, ts_str = parse_ts(fallback_ts, fallback_epoch)
    return {
        "epoch": epoch,
        "timestamp": ts_str,
        "host": peer or "unknown",
        "facility": "user",
        "severity": "info",
        "tag": "",
        "message": line,
    }


def _check_regex(pattern, field_label):
    if not pattern:
        return None
    try:
        return re.compile(str(pattern))
    except re.error as exc:
        raise ValueError(f"Invalid regex in {field_label} ('{pattern}'): {exc}") from exc


def _valid_sev(val, label):
    """Validate severity token against SEVERITY_ORDER and SEVERITY_ALIASES."""
    s = str(val or "").strip().lower()
    canon = SEVERITY_ALIASES.get(s, s)
    if canon not in SEVERITY_ORDER:
        raise ValueError(f"{label} '{s}'")
    return canon


def validate_rules(raw_yaml):
    """Parse and validate YAML rules document; returns (normalized_yaml, parsed_dict)."""
    txt = (raw_yaml or "").strip()
    if not txt:
        txt = DEFAULT_RULES_YAML

    try:
        doc = yaml.safe_load(txt)
    except yaml.YAMLError as exc:
        raise ValueError(f"YAML syntax error: {exc}") from exc

    if doc is None:
        doc = {}

    if not isinstance(doc, dict):
        raise ValueError("Root YAML document must be a mapping")

    alerts_out = []
    seen_names = set()
    raw_alerts = doc.get("alerts") or []
    if not isinstance(raw_alerts, list):
        raise ValueError("'alerts' must be a list")

    for idx, item in enumerate(raw_alerts):
        if not isinstance(item, dict):
            raise ValueError(f"Alert #{idx + 1} must be an object")

        name = str(item.get("name") or "").strip()
        if not name:
            raise ValueError(f"Alert #{idx + 1} is missing 'name'")
        if name in seen_names:
            raise ValueError(f"Duplicate alert name '{name}'")
        seen_names.add(name)

        count = int(item.get("count", 1))
        if count < 1:
            raise ValueError(f"Alert '{name}' count must be >= 1")

        win = int(item.get("window_minutes", 5))
        if win < 1:
            raise ValueError(f"Alert '{name}' window_minutes must be >= 1")

        lvl_raw = _valid_sev(item.get("level"), f"Alert '{name}' has invalid level")

        _check_regex(item.get("tag", ""), f"alert '{name}' tag")
        _check_regex(item.get("message", ""), f"alert '{name}' message")

        clean = {
            "name": name,
            "count": count,
            "window_minutes": win,
            "level": lvl_raw,
            "above": bool(item.get("above", False)),
        }
        for opt_key in ("host", "facility", "tag", "message"):
            val = str(item.get(opt_key) or "").strip()
            if val:
                clean[opt_key] = val
        alerts_out.append(clean)

    ignores_out = []
    raw_ignores = doc.get("ignore") or []
    if not isinstance(raw_ignores, list):
        raise ValueError("'ignore' must be a list")

    for idx, item in enumerate(raw_ignores):
        if not isinstance(item, dict):
            raise ValueError(f"Ignore rule #{idx + 1} must be an object")

        lvl_in = str(item.get("level") or "").strip()
        lvl = _valid_sev(lvl_in, f"Ignore rule #{idx + 1} has invalid level") if lvl_in else ""

        _check_regex(item.get("tag", ""), f"ignore #{idx + 1} tag")
        _check_regex(item.get("message", ""), f"ignore #{idx + 1} message")

        clean = {}
        for opt_key in ("host", "facility", "tag", "message"):
            val = str(item.get(opt_key) or "").strip()
            if val:
                clean[opt_key] = val
        if lvl:
            clean["level"] = lvl
        if not clean:
            raise ValueError(f"Ignore rule #{idx + 1} must specify at least one matcher")
        clean["discard"] = bool(item.get("discard", False))
        ignores_out.append(clean)

    rewrites_out = []
    raw_rewrites = doc.get("severity_rewrite") or []
    if not isinstance(raw_rewrites, list):
        raise ValueError("'severity_rewrite' must be a list")

    for idx, item in enumerate(raw_rewrites):
        if not isinstance(item, dict):
            raise ValueError(f"Severity rewrite #{idx + 1} must be an object")

        lvl_in = str(item.get("level") or "").strip()
        lvl = _valid_sev(lvl_in, f"Severity rewrite #{idx + 1} has invalid level") if lvl_in else ""
        new_sev = _valid_sev(item.get("new_severity"), f"Severity rewrite #{idx + 1} has invalid new_severity")

        _check_regex(item.get("tag", ""), f"severity_rewrite #{idx + 1} tag")
        _check_regex(item.get("message", ""), f"severity_rewrite #{idx + 1} message")

        clean = {}
        for opt_key in ("host", "facility", "tag", "message"):
            val = str(item.get(opt_key) or "").strip()
            if val:
                clean[opt_key] = val
        if lvl:
            clean["level"] = lvl
        clean["new_severity"] = new_sev
        rewrites_out.append(clean)

    raw_digest = doc.get("digest") or {}
    if not isinstance(raw_digest, dict):
        raise ValueError("'digest' must be an object")

    initial_str = str(raw_digest.get("initial", DEFAULT_DIGEST_CFG["initial"])).strip()
    max_str = str(raw_digest.get("max", DEFAULT_DIGEST_CFG["max"])).strip()
    cooldown_str = str(raw_digest.get("cooldown", DEFAULT_DIGEST_CFG["cooldown"])).strip()
    mult = float(raw_digest.get("multiplier", DEFAULT_DIGEST_CFG["multiplier"]))

    if mult < 1.5:
        raise ValueError("digest.multiplier must be >= 1.5")

    init_sec = parse_dur(initial_str)
    max_sec = parse_dur(max_str)
    parse_dur(cooldown_str)
    if max_sec < init_sec:
        raise ValueError("digest.max must be >= digest.initial")

    digest_out = {
        "enabled": bool(raw_digest.get("enabled", False)),
        "initial": initial_str,
        "multiplier": int(mult) if mult.is_integer() else mult,
        "max": max_str,
        "cooldown": cooldown_str,
    }

    parsed = {
        "alerts": alerts_out,
        "ignore": ignores_out,
        "severity_rewrite": rewrites_out,
        "digest": digest_out,
    }
    norm_yaml = yaml.safe_dump(parsed, sort_keys=False, default_flow_style=False)
    return norm_yaml, parsed


def compile_rules(parsed):
    """Precompile regexes on validated rules dict for fast ingest & query."""
    compiled = {
        "alerts": [],
        "ignore": [],
        "severity_rewrite": [],
        "digest": parsed.get("digest", dict(DEFAULT_DIGEST_CFG)),
    }
    for rule in parsed.get("ignore", []):
        compiled["ignore"].append({
            **rule,
            "_tag_re": _check_regex(rule.get("tag"), "tag"),
            "_msg_re": _check_regex(rule.get("message"), "message"),
        })
    for rule in parsed.get("severity_rewrite", []):
        compiled["severity_rewrite"].append({
            **rule,
            "_tag_re": _check_regex(rule.get("tag"), "tag"),
            "_msg_re": _check_regex(rule.get("message"), "message"),
        })
    for rule in parsed.get("alerts", []):
        compiled["alerts"].append({
            **rule,
            "_tag_re": _check_regex(rule.get("tag"), "tag"),
            "_msg_re": _check_regex(rule.get("message"), "message"),
        })
    return compiled


def match_rule(rule, entry, target=RuleTarget.DISCARD):
    """Check if log entry matches rule (exact host/facility/level, regex tag/message)."""
    if rule.get("host") and entry.get("host") != rule["host"]:
        return False

    if rule.get("facility") and entry.get("facility") != rule["facility"]:
        return False

    if rule.get("level"):
        sev = entry.get("severity", "")
        if target == RuleTarget.ALERT and rule.get("above"):
            if sev not in sev_at_or_above(rule["level"]):
                return False
        elif sev != rule["level"]:
            return False

    if rule.get("tag"):
        tag_re = rule.get("_tag_re") or re.compile(rule["tag"])
        if not tag_re.search(entry.get("tag", "")):
            return False

    if rule.get("message"):
        msg_re = rule.get("_msg_re") or re.compile(rule["message"])
        if not msg_re.search(entry.get("message", "")):
            return False

    return True


def should_discard(compiled_rules, entry):
    """Return True when entry matches any ignore rule with discard=True."""
    for rule in compiled_rules.get("ignore", []):
        if not rule.get("discard"):
            continue
        if match_rule(rule, entry, RuleTarget.DISCARD):
            return True
    return False


def apply_rewrite(compiled_rules, entry):
    """Apply first matching severity_rewrite rule and return updated severity."""
    for rule in compiled_rules.get("severity_rewrite", []):
        if match_rule(rule, entry, RuleTarget.REWRITE):
            return rule["new_severity"]
    return entry["severity"]


def _extract_from_header(fmt_text):
    if not fmt_text:
        return ""
    for line in str(fmt_text).splitlines():
        if line.lower().startswith("from:"):
            val = line.split(":", 1)[1].strip()
            m = re.search(r"<([^>]+)>", val)
            return m.group(1).strip() if m else val
    return ""


def load_config(xml_path=CONFIG_XML_PATH):
    """Load os-logwatch settings, Monit SMTP fallback, and rules from config.xml."""
    cfg = PluginConfig()
    if not os.path.exists(xml_path):
        _, parsed = validate_rules(DEFAULT_RULES_YAML)
        cfg.rules = compile_rules(parsed)
        return cfg

    root = ET.parse(xml_path).getroot()

    sys_host = (root.findtext("system/hostname") or "opnsense").strip()
    sys_dom = (root.findtext("system/domain") or "").strip()
    cfg.hostname = f"{sys_host}.{sys_dom}" if sys_dom else sys_host

    ly_gen = root.find("OPNsense/logwatch/general")
    if ly_gen is not None:
        cfg.enabled = (ly_gen.findtext("enabled") or "1") == "1"
        raw_if = (ly_gen.findtext("listen_interfaces") or "lan").strip()
        cfg.listen_interfaces = [i.strip() for i in raw_if.split(",") if i.strip()] or ["lan"]
        cfg.listen_port = int(ly_gen.findtext("listen_port") or DEFAULT_PORT)
        cfg.enable_udp = (ly_gen.findtext("enable_udp") or "1") == "1"
        cfg.enable_tcp = (ly_gen.findtext("enable_tcp") or "1") == "1"
        cfg.auto_firewall = (ly_gen.findtext("auto_firewall") or "1") == "1"
        cfg.capture_local = (ly_gen.findtext("capture_local") or "1") == "1"
        raw_excl = (ly_gen.findtext("excluded_programs") or "").strip()
        cfg.excluded_programs = {p.strip() for p in raw_excl.split(",") if p.strip()}
        cfg.min_local_severity = norm_sev(ly_gen.findtext("min_local_severity") or "info")
        cfg.retention_days = max(1, int(ly_gen.findtext("retention_days") or DEFAULT_RETENTION_DAYS))
        cfg.max_db_size_mb = max(10, int(ly_gen.findtext("max_db_size_mb") or DEFAULT_MAX_DB_MB))
        cfg.external_url = (ly_gen.findtext("external_url") or "").strip()

        use_monit = (ly_gen.findtext("use_monit_smtp") or "1") == "1"
        custom_smtp = SmtpConfig(
            host=(ly_gen.findtext("smtp_host") or "").strip(),
            port=int(ly_gen.findtext("smtp_port") or DEFAULT_SMTP_PORT),
            user=(ly_gen.findtext("smtp_user") or "").strip(),
            password=(ly_gen.findtext("smtp_password") or "").strip(),
            from_addr=(ly_gen.findtext("smtp_from") or "").strip(),
            to_addr=(ly_gen.findtext("smtp_to") or "").strip(),
            use_ssl=True,
            ssl_verify=False,
            source="custom",
        )
    else:
        use_monit = True
        custom_smtp = SmtpConfig(source="custom")

    if use_monit:
        cfg.smtp = _load_monit_smtp(root, custom_smtp)
    else:
        cfg.smtp = custom_smtp

    raw_yaml = (root.findtext("OPNsense/logwatch/rules/yaml_content") or "").strip()
    if not raw_yaml:
        raw_yaml = DEFAULT_RULES_YAML

    cfg.rules_yaml = raw_yaml
    _, parsed = validate_rules(raw_yaml)
    cfg.rules = compile_rules(parsed)
    return cfg


def _load_monit_smtp(root, overrides):
    monit_gen = root.find("OPNsense/monit/general")
    smtp = SmtpConfig(source="monit")
    if monit_gen is not None:
        smtp.host = (monit_gen.findtext("mailserver") or "").split(",")[0].strip()
        smtp.port = int(monit_gen.findtext("port") or DEFAULT_SMTP_PORT)
        smtp.user = (monit_gen.findtext("username") or "").strip()
        smtp.password = (monit_gen.findtext("password") or "").strip()
        smtp.use_ssl = (monit_gen.findtext("ssl") or "1") == "1"
        smtp.ssl_verify = (monit_gen.findtext("sslverify") or "1") == "1"

    # Find first enabled non-placeholder alert recipient & From header
    for alert in root.findall("OPNsense/monit/alert"):
        if (alert.findtext("enabled") or "0") != "1":
            continue
        recip = (alert.findtext("recipient") or "").strip()
        if recip and recip != "root@localhost.local":
            smtp.to_addr = recip
        from_hdr = _extract_from_header(alert.findtext("format"))
        if from_hdr:
            smtp.from_addr = from_hdr
        if smtp.to_addr:
            break

    if overrides.host:
        smtp.host = overrides.host
        smtp.port = overrides.port
    if overrides.user:
        smtp.user = overrides.user
    if overrides.password:
        smtp.password = overrides.password
    if overrides.from_addr:
        smtp.from_addr = overrides.from_addr
    if overrides.to_addr:
        smtp.to_addr = overrides.to_addr
    if not smtp.from_addr:
        smtp.from_addr = smtp.user

    return smtp


@lru_cache(maxsize=256)
def _compiled_rx(pattern):
    return re.compile(pattern)


def _sqlite_regexp(pattern, value):
    if value is None or pattern is None:
        return False
    try:
        return _compiled_rx(str(pattern)).search(str(value)) is not None
    except re.error:
        return False


def open_db(db_path=DB_PATH):
    """Open SQLite WAL connection with REGEXP support and ensure schema exists."""
    parent = os.path.dirname(db_path)
    if parent:
        os.makedirs(parent, exist_ok=True)

    conn = sqlite3.connect(db_path, timeout=5.0, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.create_function("REGEXP", 2, _sqlite_regexp)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA busy_timeout=5000")

    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            epoch INTEGER NOT NULL,
            host TEXT NOT NULL DEFAULT '',
            facility TEXT NOT NULL DEFAULT '',
            severity TEXT NOT NULL DEFAULT '',
            tag TEXT NOT NULL DEFAULT '',
            message TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_logs_epoch ON logs(epoch DESC, id DESC);
        CREATE INDEX IF NOT EXISTS idx_logs_sev_epoch ON logs(severity, epoch DESC);
        CREATE INDEX IF NOT EXISTS idx_logs_host_epoch ON logs(host, epoch DESC);
        CREATE INDEX IF NOT EXISTS idx_logs_tag_epoch ON logs(tag, epoch DESC);

        CREATE TABLE IF NOT EXISTS alert_state (
            rule_name TEXT PRIMARY KEY,
            last_alerted_at INTEGER NOT NULL DEFAULT 0,
            last_count INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS digest_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_name TEXT NOT NULL,
            count INTEGER NOT NULL,
            window_minutes INTEGER NOT NULL,
            level TEXT NOT NULL,
            above INTEGER NOT NULL DEFAULT 0,
            triggered_at INTEGER NOT NULL,
            sample_json TEXT NOT NULL DEFAULT '[]'
        );

        CREATE TABLE IF NOT EXISTS digest_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
    )
    return conn


def insert_logs(conn, entries):
    """Insert batch of normalized log dicts into SQLite."""
    if not entries:
        return

    rows = [
        (
            e["timestamp"],
            int(e["epoch"]),
            e.get("host", ""),
            e.get("facility", ""),
            e.get("severity", "info"),
            e.get("tag", ""),
            e.get("message", ""),
        )
        for e in entries
    ]
    conn.executemany(
        "INSERT INTO logs (timestamp, epoch, host, facility, severity, tag, message) VALUES (?, ?, ?, ?, ?, ?, ?)",
        rows,
    )
    conn.commit()


def _build_where(filters):
    clauses = []
    params = []

    if filters.get("host"):
        clauses.append("host = ?")
        params.append(filters["host"])

    if filters.get("facility"):
        clauses.append("facility = ?")
        params.append(filters["facility"])

    if filters.get("tag"):
        clauses.append("tag = ?")
        params.append(filters["tag"])

    if filters.get("severity"):
        sevs = sev_at_or_above(filters["severity"])
        marks = ",".join("?" for _ in sevs)
        clauses.append(f"severity IN ({marks})")
        params.extend(sevs)

    search = (filters.get("search") or "").strip()
    if search:
        mode = filters.get("search_mode", SearchMode.SUBSTRING)
        if mode == SearchMode.REGEX or str(mode) == "regex":
            _check_regex(search, "search")
            clauses.append("(message REGEXP ? OR tag REGEXP ? OR host REGEXP ?)")
            params.extend([search, search, search])
        else:
            clauses.append("(message LIKE ? OR tag LIKE ? OR host LIKE ?)")
            like = f"%{search}%"
            params.extend([like, like, like])

    if filters.get("since"):
        clauses.append("epoch >= ?")
        params.append(int(filters["since"]))

    if filters.get("until"):
        clauses.append("epoch <= ?")
        params.append(int(filters["until"]))

    where_sql = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    return where_sql, params


def query_logs(conn, filters):
    """Query logs matching filters and return dict with rows and count."""
    where_sql, params = _build_where(filters)
    limit = int(filters.get("limit", DEFAULT_QUERY_LIMIT))
    offset = max(0, int(filters.get("offset", 0)))

    sql = f"SELECT id, timestamp, epoch, host, facility, severity, tag, message FROM logs{where_sql} ORDER BY id DESC"
    q_params = list(params)
    if limit > 0:
        sql += " LIMIT ? OFFSET ?"
        q_params.extend([limit, offset])

    rows = [dict(r) for r in conn.execute(sql, q_params).fetchall()]
    total_row = conn.execute(f"SELECT COUNT(*) AS cnt FROM logs{where_sql}", params).fetchone()
    total = int(total_row["cnt"]) if total_row else len(rows)
    return {"rows": rows, "total": total}


def get_filters(conn, active=None):
    """Return cross-filtered distinct values for host, facility, severity, tag."""
    active = active or {}
    out = {}
    cols = ("host", "facility", "severity", "tag")
    for col in cols:
        sub = {k: v for k, v in active.items() if k != col and k in cols and v}
        where_sql, params = _build_where(sub)
        conj = " AND " if where_sql else " WHERE "
        sql = f"SELECT DISTINCT {col} FROM logs{where_sql}{conj}{col} != '' ORDER BY {col}"
        vals = [r[0] for r in conn.execute(sql, params).fetchall()]
        if col == "severity":
            order_map = {s: i for i, s in enumerate(SEVERITY_ORDER)}
            vals.sort(key=lambda x: order_map.get(x, 99))
        out[col] = vals
    return out


def prune_logs(conn, db_path, retention_days, max_db_size_mb, now_epoch=None):
    """Delete logs older than retention_days and enforce max_db_size_mb cap."""
    now = int(now_epoch if now_epoch is not None else time.time())
    cutoff = now - int(retention_days) * 86400
    cur = conn.execute("DELETE FROM logs WHERE epoch < ?", (cutoff,))
    deleted = cur.rowcount or 0
    conn.commit()

    max_bytes = int(max_db_size_mb) * 1024 * 1024
    if max_bytes > 0 and os.path.exists(db_path):
        size_bytes = os.path.getsize(db_path)
        if size_bytes > max_bytes:
            total = conn.execute("SELECT COUNT(*) FROM logs").fetchone()[0]
            drop_cnt = max(1, (total * PRUNE_BATCH_PCT) // 100)
            conn.execute(
                "DELETE FROM logs WHERE id IN (SELECT id FROM logs ORDER BY id ASC LIMIT ?)",
                (drop_cnt,),
            )
            conn.commit()
            conn.execute("VACUUM")
            deleted += drop_cnt

    return deleted


def _build_ignore_sql(ignore_rules):
    if not ignore_rules:
        return "", []

    neg_clauses = []
    params = []
    for rule in ignore_rules:
        parts = []
        if rule.get("host"):
            parts.append("host = ?")
            params.append(rule["host"])
        if rule.get("facility"):
            parts.append("facility = ?")
            params.append(rule["facility"])
        if rule.get("level"):
            parts.append("severity = ?")
            params.append(rule["level"])
        if rule.get("tag"):
            parts.append("tag REGEXP ?")
            params.append(rule["tag"])
        if rule.get("message"):
            parts.append("message REGEXP ?")
            params.append(rule["message"])
        if parts:
            neg_clauses.append("NOT (" + " AND ".join(parts) + ")")

    if not neg_clauses:
        return "", []

    return " AND " + " AND ".join(neg_clauses), params


def _build_alert_where(rule, ignore_rules, since_epoch):
    clauses = ["epoch >= ?"]
    params = [int(since_epoch)]

    if rule.get("above"):
        sevs = sev_at_or_above(rule["level"])
        marks = ",".join("?" for _ in sevs)
        clauses.append(f"severity IN ({marks})")
        params.extend(sevs)
    else:
        clauses.append("severity = ?")
        params.append(rule["level"])

    if rule.get("host"):
        clauses.append("host = ?")
        params.append(rule["host"])

    if rule.get("facility"):
        clauses.append("facility = ?")
        params.append(rule["facility"])

    if rule.get("tag"):
        clauses.append("tag REGEXP ?")
        params.append(rule["tag"])

    if rule.get("message"):
        clauses.append("message REGEXP ?")
        params.append(rule["message"])

    ign_sql, ign_params = _build_ignore_sql(ignore_rules)
    sql = " WHERE " + " AND ".join(clauses) + ign_sql
    params.extend(ign_params)
    return sql, params


def eval_alert_rule(conn, rule, ignore_rules, now_epoch=None):
    """Evaluate one alert rule; returns (count, sample_rows) if triggered else (0, [])."""
    now = int(now_epoch if now_epoch is not None else time.time())
    since = now - int(rule["window_minutes"]) * 60

    row = conn.execute(
        "SELECT last_alerted_at FROM alert_state WHERE rule_name = ?",
        (rule["name"],),
    ).fetchone()
    if row and int(row["last_alerted_at"]) >= since:
        return 0, []

    where_sql, params = _build_alert_where(rule, ignore_rules, since)
    cnt = int(conn.execute(f"SELECT COUNT(*) FROM logs{where_sql}", params).fetchone()[0])
    if cnt < int(rule["count"]):
        return 0, []

    samples = [
        dict(r)
        for r in conn.execute(
            f"SELECT timestamp, host, facility, severity, tag, message FROM logs{where_sql} ORDER BY id DESC LIMIT ?",
            [*params, ALERT_SAMPLE_LIMIT],
        ).fetchall()
    ]
    return cnt, samples


def mark_alerted(conn, rule_name, count, now_epoch=None):
    """Record trigger timestamp and count for rule cooldown tracking."""
    now = int(now_epoch if now_epoch is not None else time.time())
    conn.execute(
        """
        INSERT INTO alert_state (rule_name, last_alerted_at, last_count)
        VALUES (?, ?, ?)
        ON CONFLICT(rule_name) DO UPDATE SET
            last_alerted_at = excluded.last_alerted_at,
            last_count = excluded.last_count
        """,
        (rule_name, now, int(count)),
    )
    conn.commit()


def _html_escape(txt):
    return (
        str(txt or "")
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def build_alert_html(title, sections, footer_url):
    """Render clean HTML email matching mietzen-logyard formatting."""
    body_blocks = []
    for sec in sections:
        rows_html = []
        for s in sec.get("samples", []):
            rows_html.append(
                "<tr>"
                f"<td style='padding:4px 8px;border-bottom:1px solid #2d3748;white-space:nowrap;'>{_html_escape(s.get('timestamp'))}</td>"
                f"<td style='padding:4px 8px;border-bottom:1px solid #2d3748;'>{_html_escape(s.get('host'))}</td>"
                f"<td style='padding:4px 8px;border-bottom:1px solid #2d3748;'>{_html_escape(s.get('severity'))}</td>"
                f"<td style='padding:4px 8px;border-bottom:1px solid #2d3748;'>{_html_escape(s.get('tag'))}</td>"
                f"<td style='padding:4px 8px;border-bottom:1px solid #2d3748;word-break:break-word;'>{_html_escape(s.get('message'))}</td>"
                "</tr>"
            )
        body_blocks.append(
            f"<h3 style='color:#63b3ed;margin:16px 0 6px;'>{_html_escape(sec['heading'])}</h3>"
            f"<p style='color:#cbd5e0;margin:0 0 8px;'>{_html_escape(sec['summary'])}</p>"
            "<table style='width:100%;border-collapse:collapse;font-family:monospace;font-size:12px;background:#1a202c;color:#e2e8f0;'>"
            "<thead><tr style='background:#2d3748;text-align:left;'>"
            "<th style='padding:6px 8px;'>Time</th><th style='padding:6px 8px;'>Host</th>"
            "<th style='padding:6px 8px;'>Severity</th><th style='padding:6px 8px;'>Tag</th>"
            "<th style='padding:6px 8px;'>Message</th></tr></thead>"
            f"<tbody>{''.join(rows_html)}</tbody></table>"
        )

    footer = ""
    if footer_url:
        footer = f"<p style='margin-top:16px;font-size:12px;'><a href='{_html_escape(footer_url)}' style='color:#63b3ed;'>Open Logwatch in OPNsense</a></p>"

    return (
        "<html><body style='background:#0f1419;color:#e2e8f0;font-family:sans-serif;padding:20px;'>"
        f"<h2 style='color:#f6ad55;margin-top:0;'>{_html_escape(title)}</h2>"
        f"{''.join(body_blocks)}{footer}</body></html>"
    )


def send_email(smtp_cfg, subject, html_body):
    """Send HTML email via STARTTLS or SMTPS using configured SMTP settings."""
    if not smtp_cfg.host or not smtp_cfg.to_addr:
        raise ValueError("SMTP host and recipient address are required")

    from_addr = smtp_cfg.from_addr or smtp_cfg.user or "logwatch@opnsense.local"
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"Logwatch <{from_addr}>"
    msg["To"] = smtp_cfg.to_addr
    msg.attach(MIMEText(html_body, "html", "utf-8"))

    ctx = ssl.create_default_context() if smtp_cfg.ssl_verify else ssl._create_unverified_context()

    if int(smtp_cfg.port) == SMTPS_PORT:
        with smtplib.SMTP_SSL(smtp_cfg.host, int(smtp_cfg.port), timeout=15, context=ctx) as client:
            if smtp_cfg.user:
                client.login(smtp_cfg.user, smtp_cfg.password)
            client.sendmail(from_addr, [a.strip() for a in smtp_cfg.to_addr.split(",") if a.strip()], msg.as_string())
        return

    with smtplib.SMTP(smtp_cfg.host, int(smtp_cfg.port), timeout=15) as client:
        client.ehlo()
        if smtp_cfg.use_ssl and client.has_extn("starttls"):
            client.starttls(context=ctx)
            client.ehlo()
        if smtp_cfg.user:
            client.login(smtp_cfg.user, smtp_cfg.password)
        client.sendmail(from_addr, [a.strip() for a in smtp_cfg.to_addr.split(",") if a.strip()], msg.as_string())


def ui_footer_url(cfg):
    """Resolve click-through link included in alert emails."""
    if cfg.external_url:
        return cfg.external_url.rstrip("/") + "/ui/logwatch/logs"
    return f"https://{cfg.hostname}/ui/logwatch/logs"
