#!/usr/local/bin/python3
"""
OPNware os-docker: dynamic PF port sync daemon & host collision detector.
Monitors published Docker container ports and manages PF anchor rules safely.
"""

import time
import json
import subprocess
import os
import re
import syslog

import xml.etree.ElementTree as ET

DOCKER_BIN = "/usr/local/bin/docker"
VM_HOST = "tcp://100.64.0.2:2375"
PF_ANCHOR = "opnware-docker/rdr"
VM_IP = "100.64.0.2"


def get_host_bound_ports():
    """Return a dictionary of { (proto, port): process_name } listening on host."""
    bound = {}
    try:
        proc = subprocess.run(["/usr/bin/sockstat", "-46l"], capture_output=True, text=True, timeout=5)
        if proc.returncode == 0:
            for line in proc.stdout.splitlines()[1:]:
                parts = line.split()
                if len(parts) >= 6:
                    user = parts[0]
                    cmd = parts[1]
                    proto = parts[4].lower()
                    addr = parts[5]
                    # match IP:PORT
                    m = re.search(r":(\d+)$", addr)
                    if m:
                        port = int(m.group(1))
                        bound[(proto, port)] = f"{cmd} ({user})"
    except Exception as e:
        syslog.syslog(syslog.LOG_WARNING, f"docker_port_sync: failed to read sockstat: {e}")
    return bound


def get_container_published_ports():
    """Return list of published port mappings from running containers."""
    ports = []
    try:
        env = os.environ.copy()
        env["DOCKER_HOST"] = VM_HOST
        proc = subprocess.run(
            [DOCKER_BIN, "-H", VM_HOST, "ps", "--format", "{{json .}}"],
            capture_output=True,
            text=True,
            timeout=10,
            env=env
        )
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    c = json.loads(line)
                    raw_ports = c.get("Ports", "")
                    name = c.get("Names", "container")
                    # e.g., "0.0.0.0:8080->80/tcp, :::8080->80/tcp, 0.0.0.0:53->53/udp"
                    matches = re.findall(r"(?:0\.0\.0\.0|:::?|\[::\]):(\d+)->(\d+)/(tcp|udp)", raw_ports)
                    for host_p, cont_p, proto in matches:
                        ports.append({
                            "container": name,
                            "host_port": int(host_p),
                            "container_port": int(cont_p),
                            "proto": proto.lower()
                        })
                except Exception:
                    pass
    except Exception:
        pass
    return ports


def get_configured_interfaces(config_path="/conf/config.xml"):
    """Get list of network interface devices from OPNsense config."""
    ifs = ["lo0"]
    try:
        if os.path.exists(config_path):
            tree = ET.parse(config_path)
            root = tree.getroot()
            selected_raw = root.findtext(".//OPNsense/docker/general/interfaces") or root.findtext(".//docker/general/interfaces") or "lan"
            selected_keys = [k.strip() for k in selected_raw.split(",") if k.strip()]
            for k in selected_keys:
                dev = root.findtext(f".//interfaces/{k}/if")
                if dev:
                    ifs.append(dev)
    except Exception as e:
        syslog.syslog(syslog.LOG_WARNING, f"docker_port_sync: error reading interfaces config: {e}")

    if len(ifs) == 1:
        return get_active_interfaces()
    return list(dict.fromkeys(ifs))


def get_active_interfaces():
    """Get list of active network interfaces to bind port forwards."""
    ifs = ["lo0"]
    try:
        proc = subprocess.run(["/sbin/ifconfig", "-l"], capture_output=True, text=True, timeout=5)
        if proc.returncode == 0:
            for iface in proc.stdout.strip().split():
                # Ignore loopbacks, tap, bridge, bhyve, and packet filter interfaces
                if not iface.startswith(("lo", "tap", "bridge", "vm-", "epair", "enc", "pflog", "pfsync")):
                    ifs.append(iface)
    except Exception:
        pass
    return ifs


def sync_pf_rules():
    host_ports = get_host_bound_ports()
    container_ports = get_container_published_ports()
    interfaces = get_configured_interfaces()

    rules = []
    active_keys = set()
    conflicts = []

    for p in container_ports:
        key = (p["proto"], p["host_port"])
        if key in active_keys:
            continue
        active_keys.add(key)

        # Check for host collision
        if key in host_ports:
            owner = host_ports[key]
            msg = f"Docker port conflict! Container '{p['container']}' requested host port {p['host_port']}/{p['proto']} which is currently bound by host process '{owner}'. Skipping port forward."
            syslog.syslog(syslog.LOG_ERR, f"docker_port_sync: {msg}")
            print(f"ERROR: {msg}", flush=True)
            conflicts.append({
                "container": p["container"],
                "port": p["host_port"],
                "proto": p["proto"],
                "owner": owner,
                "message": msg
            })
            continue

        # Build PF redirect rules for all host interfaces
        for iface in interfaces:
            rules.append(
                f"rdr on {iface} proto {p['proto']} from any to ({iface}) port {p['host_port']} -> {VM_IP} port {p['host_port']}"
            )

    # Save conflict status for WebUI dashboard
    try:
        os.makedirs("/var/db/os-docker", mode=0o755, exist_ok=True)
        with open("/var/db/os-docker/conflicts.json", "w") as f:
            json.dump(conflicts, f)
    except Exception:
        pass

    rules_text = "\n".join(rules) + "\n" if rules else ""
    try:
        proc = subprocess.run(
            ["/sbin/pfctl", "-a", PF_ANCHOR, "-f", "-"],
            input=rules_text,
            text=True,
            capture_output=True,
            timeout=5
        )
        if proc.returncode != 0:
            syslog.syslog(syslog.LOG_WARNING, f"docker_port_sync: pfctl failed: {proc.stderr}")
    except Exception as e:
        syslog.syslog(syslog.LOG_WARNING, f"docker_port_sync: pfctl exception: {e}")


def main():
    syslog.openlog(ident="docker-port-sync", facility=syslog.LOG_DAEMON)
    syslog.syslog(syslog.LOG_INFO, "Docker dynamic port sync daemon started.")

    while True:
        try:
            sync_pf_rules()
        except Exception as e:
            syslog.syslog(syslog.LOG_WARNING, f"docker_port_sync loop error: {e}")
        time.sleep(3)


if __name__ == "__main__":
    main()
