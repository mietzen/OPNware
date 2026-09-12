#!/usr/local/bin/python3
"""
OPNware os-docker: backend management CLI runner.
Dispatches container, image, volume, and system operations and formats JSON output.
"""

import sys
import json
import subprocess
import os
import re

STATUS_FILE = "/var/db/os-docker/manage_status.json"
DOCKER_BIN = "/usr/local/bin/docker"
SSH_KEY = "/var/db/os-docker/id_ed25519"
VM_HOST = "tcp://100.64.0.2:2375"


def write_status(data):
    try:
        os.makedirs("/var/db/os-docker", mode=0o755, exist_ok=True)
        with open(STATUS_FILE, "w") as f:
            json.dump(data, f)
    except Exception:
        pass


def run_docker(args):
    if not os.path.exists(DOCKER_BIN):
        res = {"status": "error", "message": f"{DOCKER_BIN} not found"}
        write_status(res)
        print(json.dumps(res))
        sys.exit(0)

    env = os.environ.copy()
    env["DOCKER_HOST"] = VM_HOST
    if os.path.exists(SSH_KEY):
        env["GIT_SSH_COMMAND"] = f"ssh -i {SSH_KEY} -o StrictHostKeyChecking=no"

    cmd = [DOCKER_BIN, "-H", VM_HOST] + args
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60, env=env)
        out = proc.stdout.strip()
        err = proc.stderr.strip()

        combined = (out + ("\n" + err if err else "")) if out else err

        if proc.returncode != 0:
            msg = combined or f"Process exited with code {proc.returncode}"
            res = {"status": "error", "message": msg, "output": combined}
            write_status(res)
            print(json.dumps(res))
            sys.exit(0)

        # Parse JSON if format is json
        if "--format" in args and "json" in args or "--format" in args and "{{json .}}" in args:
            if not out:
                res = {"status": "ok", "items": []}
            else:
                items = []
                try:
                    parsed = json.loads(out)
                    if isinstance(parsed, list):
                        items = parsed
                    else:
                        items = [parsed]
                except Exception:
                    # Docker sometimes returns multiple JSON lines (NDJSON)
                    for line in out.splitlines():
                        line = line.strip()
                        if line:
                            try:
                                items.append(json.loads(line))
                            except Exception:
                                pass
                res = {"status": "ok", "items": items}
        else:
            res = {"status": "ok", "output": combined}

        write_status(res)
        print(json.dumps(res))
        sys.exit(0)
    except subprocess.TimeoutExpired:
        res = {"status": "error", "message": "Command timed out after 60s"}
        write_status(res)
        print(json.dumps(res))
        sys.exit(0)
    except Exception as e:
        res = {"status": "error", "message": str(e)}
        write_status(res)
        print(json.dumps(res))
        sys.exit(0)


def main():
    if len(sys.argv) < 2:
        res = {"status": "error", "message": "Missing command argument"}
        print(json.dumps(res))
        sys.exit(0)

    action = sys.argv[1]
    param = sys.argv[2] if len(sys.argv) >= 3 else None

    # Containers
    if action == "containers_list":
        run_docker(["ps", "-a", "--format", "{{json .}}"])
    elif action == "containers_start" and param:
        run_docker(["start", "--", param])
    elif action == "containers_stop" and param:
        run_docker(["stop", "--", param])
    elif action == "containers_kill" and param:
        run_docker(["kill", "--", param])
    elif action == "containers_restart" and param:
        run_docker(["restart", "--", param])
    elif action == "containers_delete" and param:
        run_docker(["rm", "-f", "--", param])
    elif action == "containers_logs" and param:
        run_docker(["logs", "--tail", "200", "--", param])
    elif action == "containers_inspect" and param:
        run_docker(["inspect", "--", param])

    # Images
    elif action == "images_list":
        run_docker(["images", "--format", "{{json .}}"])
    elif action == "images_pull" and param:
        run_docker(["pull", "--", param])
    elif action == "images_delete" and param:
        run_docker(["rmi", "-f", "--", param])
    elif action == "images_prune":
        run_docker(["image", "prune", "-f"])

    # Volumes
    elif action == "volumes_list":
        run_docker(["volume", "ls", "--format", "{{json .}}"])
    elif action == "volumes_create" and param:
        run_docker(["volume", "create", "--", param])
    elif action == "volumes_inspect" and param:
        run_docker(["volume", "inspect", "--", param])
    elif action == "volumes_delete" and param:
        run_docker(["volume", "rm", "-f", "--", param])
    elif action == "volumes_prune":
        run_docker(["volume", "prune", "-f"])

    # Networks
    elif action == "networks_list":
        run_docker(["network", "ls", "--format", "{{json .}}"])
    elif action == "networks_inspect" and param:
        run_docker(["network", "inspect", "--", param])
    elif action == "networks_delete" and param:
        run_docker(["network", "rm", "--", param])

    # System
    elif action == "system_df":
        run_docker(["system", "df", "--format", "{{json .}}"])
    elif action == "system_stats":
        run_docker(["stats", "--no-stream", "--format", "{{json .}}"])
    elif action == "system_info":
        run_docker(["info", "--format", "{{json .}}"])
    elif action == "system_prune":
        run_docker(["system", "prune", "-f"])
    elif action == "metrics":
        ssh_bin = "/usr/local/bin/ssh" if os.path.exists("/usr/local/bin/ssh") else "/usr/bin/ssh"
        ssh_cmd = [
            ssh_bin,
            "-i", SSH_KEY,
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=2",
            "-o", "BatchMode=yes",
            "root@100.64.0.2",
            "cat /proc/loadavg; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; df -k /var/lib/docker"
        ]
        res = {
            "status": "ok",
            "running": False,
            "cpu": {"display": "--", "load_1m": 0, "percent": 0, "vcpus": 2},
            "ram": {"display": "--", "used_mb": 0, "total_mb": 0, "percent": 0},
            "disk": {"display": "--", "used_gb": 0, "total_gb": 0, "percent": 0}
        }
        try:
            proc = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=4)
            if proc.returncode == 0 and proc.stdout.strip():
                lines = [l.strip() for l in proc.stdout.splitlines() if l.strip()]
                if lines:
                    res["running"] = True
                    load_parts = lines[0].split()
                    l1 = float(load_parts[0]) if len(load_parts) > 0 else 0.0
                    l5 = float(load_parts[1]) if len(load_parts) > 1 else 0.0
                    l15 = float(load_parts[2]) if len(load_parts) > 2 else 0.0
                    vcpus = os.cpu_count() or 2
                    cpu_pct = min(100, round((l1 / max(1, vcpus)) * 100, 1))
                    res["cpu"] = {
                        "load_1m": l1,
                        "load_5m": l5,
                        "load_15m": l15,
                        "percent": cpu_pct,
                        "vcpus": vcpus,
                        "display": f"{l1:.2f}, {l5:.2f}, {l15:.2f} ({vcpus} vCPUs)"
                    }
                    mem_total = 0
                    mem_avail = 0
                    for l in lines:
                        if l.startswith("MemTotal:"):
                            m = re.search(r"(\d+)", l)
                            if m:
                                mem_total = int(m.group(1))
                        elif l.startswith("MemAvailable:"):
                            m = re.search(r"(\d+)", l)
                            if m:
                                mem_avail = int(m.group(1))
                    if mem_total > 0:
                        mem_used = max(0, mem_total - mem_avail)
                        used_mb = round(mem_used / 1024)
                        total_mb = round(mem_total / 1024)
                        mem_pct = round((used_mb / max(1, total_mb)) * 100, 1)
                        res["ram"] = {
                            "used_mb": used_mb,
                            "total_mb": total_mb,
                            "percent": mem_pct,
                            "display": f"{used_mb} MB / {total_mb} MB ({mem_pct:.1f}%)"
                        }
                    for l in lines:
                        if "/var/lib/docker" in l:
                            cols = l.split()
                            if len(cols) >= 5:
                                total_kb = int(cols[1])
                                used_kb = int(cols[2])
                                total_gb = round(total_kb / (1024 * 1024), 1)
                                used_gb = round(used_kb / (1024 * 1024), 2)
                                disk_pct = round((used_kb / total_kb) * 100, 1) if total_kb > 0 else 0
                                res["disk"] = {
                                    "used_gb": used_gb,
                                    "total_gb": total_gb,
                                    "percent": disk_pct,
                                    "display": f"{used_gb:.2f} GB / {total_gb:.1f} GB ({disk_pct:.1f}%)"
                                }
                            break
        except Exception as e:
            res["error"] = str(e)
        print(json.dumps(res))
        sys.exit(0)

    else:
        res = {"status": "error", "message": f"Unknown action: {action}"}
        print(json.dumps(res))
        sys.exit(0)


if __name__ == "__main__":
    main()
