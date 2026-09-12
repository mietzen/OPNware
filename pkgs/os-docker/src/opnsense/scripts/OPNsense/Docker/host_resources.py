#!/usr/local/bin/python3
"""
OPNware os-docker: query host CPU, RAM, and storage resources.
"""

import json
import os
import subprocess


def get_host_resources():
    cpus = 2
    try:
        proc = subprocess.run(["/sbin/sysctl", "-n", "hw.ncpu"], capture_output=True, text=True, timeout=5)
        if proc.returncode == 0 and proc.stdout.strip().isdigit():
            cpus = int(proc.stdout.strip())
    except Exception:
        pass

    memory_mb = 2048
    try:
        proc = subprocess.run(["/sbin/sysctl", "-n", "hw.realmem"], capture_output=True, text=True, timeout=5)
        if proc.returncode != 0 or not proc.stdout.strip().isdigit():
            proc = subprocess.run(["/sbin/sysctl", "-n", "hw.physmem"], capture_output=True, text=True, timeout=5)
        if proc.returncode == 0 and proc.stdout.strip().isdigit():
            memory_bytes = int(proc.stdout.strip())
            raw_mb = memory_bytes / (1024 * 1024)
            memory_mb = max(512, int(round(raw_mb / 512.0) * 512))
    except Exception:
        pass

    disk_free_gb = 50
    try:
        stat = os.statvfs("/var/db")
        disk_free_gb = (stat.f_bavail * stat.f_frsize) // (1024 * 1024 * 1024)
    except Exception:
        pass

    return {
        "status": "ok",
        "cpus": cpus,
        "memory_mb": memory_mb,
        "disk_free_gb": disk_free_gb
    }


def main():
    print(json.dumps(get_host_resources()))


if __name__ == "__main__":
    main()
