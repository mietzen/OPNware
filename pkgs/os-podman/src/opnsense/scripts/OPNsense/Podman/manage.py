#!/usr/local/bin/python3
"""
OPNware os-podman: backend management CLI runner.
Dispatches container, image, volume, network, and system operations and formats JSON output.
"""

import sys
import json
import subprocess
import os

STATUS_FILE = "/var/db/podman/manage_status.json"
PODMAN_BIN = "/usr/local/bin/podman"


def write_status(data):
    try:
        os.makedirs("/var/db/podman", mode=0o755, exist_ok=True)
        with open(STATUS_FILE, "w") as f:
            json.dump(data, f)
    except Exception:
        pass


def run_podman(args):
    if not os.path.exists(PODMAN_BIN):
        res = {"status": "error", "message": f"{PODMAN_BIN} not found"}
        write_status(res)
        print(json.dumps(res))
        sys.exit(0)

    cmd = [PODMAN_BIN] + args
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        out = proc.stdout.strip()
        err = proc.stderr.strip()

        if proc.returncode != 0:
            res = {"status": "error", "message": err or f"Process exited with code {proc.returncode}"}
            write_status(res)
            print(json.dumps(res))
            sys.exit(0)

        # Parse JSON if output is json format
        if "--format" in args and "json" in args:
            if not out:
                res = {"status": "ok", "items": []}
            else:
                try:
                    parsed = json.loads(out)
                    if isinstance(parsed, list):
                        res = {"status": "ok", "items": parsed}
                    else:
                        res = {"status": "ok", "items": [parsed]}
                except Exception:
                    res = {"status": "ok", "items": [], "raw": out}
        else:
            res = {"status": "ok", "output": out}

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

    # Containers
    if action == "containers.list":
        run_podman(["ps", "-a", "--format", "json"])
    elif action == "containers.start" and len(sys.argv) >= 3:
        run_podman(["start", sys.argv[2]])
    elif action == "containers.stop" and len(sys.argv) >= 3:
        run_podman(["stop", sys.argv[2]])
    elif action == "containers.kill" and len(sys.argv) >= 3:
        run_podman(["kill", sys.argv[2]])
    elif action == "containers.restart" and len(sys.argv) >= 3:
        run_podman(["restart", sys.argv[2]])
    elif action == "containers.delete" and len(sys.argv) >= 3:
        run_podman(["rm", "-f", sys.argv[2]])
    elif action == "containers.logs" and len(sys.argv) >= 3:
        run_podman(["logs", "--tail", "200", sys.argv[2]])
    elif action == "containers.inspect" and len(sys.argv) >= 3:
        run_podman(["inspect", sys.argv[2], "--format", "json"])

    # Images
    elif action == "images.list":
        run_podman(["images", "--format", "json"])
    elif action == "images.delete" and len(sys.argv) >= 3:
        run_podman(["rmi", "-f", sys.argv[2]])

    # Volumes
    elif action == "volumes.list":
        run_podman(["volume", "ls", "--format", "json"])
    elif action == "volumes.delete" and len(sys.argv) >= 3:
        run_podman(["volume", "rm", "-f", sys.argv[2]])

    # Networks
    elif action == "networks.list":
        run_podman(["network", "ls", "--format", "json"])
    elif action == "networks.delete" and len(sys.argv) >= 3:
        run_podman(["network", "rm", sys.argv[2]])

    # System
    elif action == "system.df":
        run_podman(["system", "df", "--format", "json"])
    elif action == "system.prune":
        run_podman(["system", "prune", "-f"])
    elif action == "system.info":
        run_podman(["info", "--format", "json"])

    else:
        res = {"status": "error", "message": f"Unknown action: {action}"}
        write_status(res)
        print(json.dumps(res))
        sys.exit(0)


if __name__ == "__main__":
    main()
