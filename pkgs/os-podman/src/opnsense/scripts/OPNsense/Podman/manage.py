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
            combined = (out + ("\n" + err if err else "")) if out else err
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
    if action == "containers.list":
        run_podman(["ps", "-a", "--format", "json"])
    elif action == "containers.start" and param:
        run_podman(["start", param])
    elif action == "containers.stop" and param:
        run_podman(["stop", param])
    elif action == "containers.kill" and param:
        run_podman(["kill", param])
    elif action == "containers.restart" and param:
        run_podman(["restart", param])
    elif action == "containers.delete" and param:
        run_podman(["rm", "-f", param])
    elif action == "containers.logs" and param:
        run_podman(["logs", "--tail", "200", param])
    elif action == "containers.inspect" and param:
        run_podman(["inspect", param, "--format", "json"])

    # Images
    elif action == "images.list":
        run_podman(["images", "--format", "json"])
    elif action == "images.delete" and param:
        run_podman(["rmi", "-f", param])

    # Volumes
    elif action == "volumes.list":
        run_podman(["volume", "ls", "--format", "json"])
    elif action == "volumes.delete" and param:
        run_podman(["volume", "rm", "-f", param])

    # Networks
    elif action == "networks.list":
        run_podman(["network", "ls", "--format", "json"])
    elif action == "networks.delete" and param:
        run_podman(["network", "rm", param])

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
