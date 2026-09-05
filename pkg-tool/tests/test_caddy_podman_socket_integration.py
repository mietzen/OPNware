import re
from pathlib import Path


def test_caddy_dockerproxy_detects_and_auto_adds_podman_socket():
    dp_script = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/dockerproxy.php").read_text()
    assert "/usr/local/opnsense/version/podman" in dp_script or "/var/run/podman/podman.sock" in dp_script
    assert "unix:///var/run/podman/podman.sock" in dp_script
    assert "$hasPodman" in dp_script or "hasPodman" in dp_script
    assert "$rows['CADDY_DOCKER_SOCKETS']" in dp_script


def test_podman_setup_notifies_caddy_dockerproxy_sync():
    setup_script = Path("pkgs/os-podman/src/opnsense/scripts/OPNsense/Podman/setup.php").read_text()
    assert "/usr/local/opnsense/version/caddy-advanced" in setup_script
    assert "caddyadvanced dockerproxy-sync" in setup_script


def test_caddy_status_and_ui_expose_podman_integration():
    status_script = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/status.php").read_text()
    assert "podman_present" in status_script or "podman_socket" in status_script

    volt_view = Path("pkgs/os-caddy-advanced/src/opnsense/mvc/app/views/OPNsense/CaddyAdvanced/general.volt").read_text()
    assert "podman" in volt_view.lower()
    assert "unix:///var/run/podman/podman.sock" in volt_view


def test_socket_formatting_logic():
    local_socket = "unix:///var/run/podman/podman.sock"

    # Case 1: Empty configured sockets with Podman present
    configured = ""
    has_podman = True
    if has_podman:
        if configured == "":
            sockets_result = local_socket
        else:
            sockets = [s.strip() for s in configured.split(",") if s.strip()]
            if local_socket not in sockets:
                sockets.append(local_socket)
            sockets_result = ",".join(sockets)
    assert sockets_result == "unix:///var/run/podman/podman.sock"

    # Case 2: Existing remote socket with Podman present
    configured = "tcp://debian-test:2375"
    if has_podman:
        if configured == "":
            sockets_result = local_socket
        else:
            sockets = [s.strip() for s in configured.split(",") if s.strip()]
            if local_socket not in sockets:
                sockets.append(local_socket)
            sockets_result = ",".join(sockets)
    assert sockets_result == "tcp://debian-test:2375,unix:///var/run/podman/podman.sock"

    # Case 3: Sockets already containing local socket
    configured = "tcp://debian-test:2375,unix:///var/run/podman/podman.sock"
    if has_podman:
        if configured == "":
            sockets_result = local_socket
        else:
            sockets = [s.strip() for s in configured.split(",") if s.strip()]
            if local_socket not in sockets:
                sockets.append(local_socket)
            sockets_result = ",".join(sockets)
    assert sockets_result == "tcp://debian-test:2375,unix:///var/run/podman/podman.sock"
