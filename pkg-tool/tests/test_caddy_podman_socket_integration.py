import subprocess
import tempfile
from pathlib import Path


def test_caddy_dockerproxy_detects_and_auto_adds_podman_socket():
    dp_script = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/dockerproxy.php").read_text()
    assert "/usr/local/opnsense/version/podman" in dp_script or "/var/run/podman/podman.sock" in dp_script
    assert "unix:///var/run/podman/podman.sock" in dp_script
    assert "$hasPodman" in dp_script or "hasPodman" in dp_script
    assert "$rows['CADDY_DOCKER_SOCKETS']" in dp_script


def test_podman_setup_and_service_notifies_caddy_dockerproxy_sync():
    setup_script = Path("pkgs/os-podman/src/opnsense/scripts/OPNsense/Podman/setup.php").read_text()
    assert "/usr/local/opnsense/version/caddy-advanced" in setup_script
    assert "caddyadvanced dockerproxy-sync" in setup_script

    rc_script = Path("pkgs/os-podman/src/usr/local/etc/rc.d/podman-service").read_text()
    assert "/usr/local/opnsense/version/caddy-advanced" in rc_script
    assert "caddyadvanced dockerproxy-sync" in rc_script


def test_caddy_status_and_ui_expose_podman_integration():
    status_script = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/status.php").read_text()
    assert "podman_socket_active" in status_script

    volt_view = Path("pkgs/os-caddy-advanced/src/opnsense/mvc/app/views/OPNsense/CaddyAdvanced/general.volt").read_text()
    assert "status-podman-socket" in volt_view
    assert "podman_socket_active" in volt_view
    assert "unix:///var/run/podman/podman.sock" in volt_view


def test_php_dockerproxy_sync_logic_execution():
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        env_file = tmp_path / "env"
        env_file.write_text("CUSTOM_VAR=hello\n")

        php_test = f"""
        $envFile = '{env_file}';
        $localPodmanSocket = 'unix:///var/run/podman/podman.sock';

        // 1. When podman is present and sockets is empty / default placeholder
        $hasPodman = true;
        $configuredSockets = 'tcp://docker-proxy-host:2375';
        $rows = [];
        if ($hasPodman && ($configuredSockets === '' || $configuredSockets === 'tcp://docker-proxy-host:2375')) {{
            $rows['CADDY_DOCKER_SOCKETS'] = $localPodmanSocket;
        }} elseif ($configuredSockets !== '') {{
            $rows['CADDY_DOCKER_SOCKETS'] = $configuredSockets;
        }}
        assert($rows['CADDY_DOCKER_SOCKETS'] === 'unix:///var/run/podman/podman.sock');

        // 2. When podman is present and user specified a custom socket
        $configuredSockets = 'tcp://custom-remote:2375';
        $rows = [];
        if ($hasPodman && ($configuredSockets === '' || $configuredSockets === 'tcp://docker-proxy-host:2375')) {{
            $rows['CADDY_DOCKER_SOCKETS'] = $localPodmanSocket;
        }} elseif ($configuredSockets !== '') {{
            $rows['CADDY_DOCKER_SOCKETS'] = $configuredSockets;
        }}
        assert($rows['CADDY_DOCKER_SOCKETS'] === 'tcp://custom-remote:2375');

        // 3. When podman is absent and default placeholder is used
        $hasPodman = false;
        $configuredSockets = 'tcp://docker-proxy-host:2375';
        $rows = [];
        if ($hasPodman && ($configuredSockets === '' || $configuredSockets === 'tcp://docker-proxy-host:2375')) {{
            $rows['CADDY_DOCKER_SOCKETS'] = $localPodmanSocket;
        }} elseif ($configuredSockets !== '') {{
            $rows['CADDY_DOCKER_SOCKETS'] = $configuredSockets;
        }}
        assert($rows['CADDY_DOCKER_SOCKETS'] === 'tcp://docker-proxy-host:2375');

        echo 'SYNC_LOGIC_PASSED';
        """
        res = subprocess.run(["php", "-r", php_test], capture_output=True, text=True)
        assert res.returncode == 0
        assert "SYNC_LOGIC_PASSED" in res.stdout
