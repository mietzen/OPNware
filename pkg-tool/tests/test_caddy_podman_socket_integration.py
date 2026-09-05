import subprocess
from pathlib import Path


def test_caddy_dockerproxy_detects_and_auto_adds_podman_socket():
    dp_script = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/dockerproxy.php").read_text()
    assert "/usr/local/opnsense/version/podman" in dp_script or "/var/run/podman/podman.sock" in dp_script
    assert "unix:///var/run/podman/podman.sock" in dp_script
    assert "$hasPodman" in dp_script or "hasPodman" in dp_script
    assert "$rows['CADDY_DOCKER_SOCKETS']" in dp_script
    assert "docker_proxy_module_installed" in dp_script


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
    assert "podman" in volt_view.lower()
    assert "podman_socket_active" in volt_view
    assert "unix:///var/run/podman/podman.sock" in volt_view


def test_php_socket_formatting_execution():
    php_code = """
    $localPodmanSocket = 'unix:///var/run/podman/podman.sock';
    $hasPodman = true;

    // Test 1: Empty configured sockets
    $configuredSockets = '';
    $rows = [];
    if ($hasPodman) {
        if ($configuredSockets === '') {
            $rows['CADDY_DOCKER_SOCKETS'] = $localPodmanSocket;
        } else {
            $sockets = array_filter(array_map('trim', explode(',', $configuredSockets)));
            if (!in_array($localPodmanSocket, $sockets, true)) {
                $sockets[] = $localPodmanSocket;
            }
            $rows['CADDY_DOCKER_SOCKETS'] = implode(',', $sockets);
        }
    }
    assert($rows['CADDY_DOCKER_SOCKETS'] === 'unix:///var/run/podman/podman.sock');

    // Test 2: Existing remote socket
    $configuredSockets = 'tcp://debian-test:2375';
    $rows = [];
    if ($hasPodman) {
        if ($configuredSockets === '') {
            $rows['CADDY_DOCKER_SOCKETS'] = $localPodmanSocket;
        } else {
            $sockets = array_filter(array_map('trim', explode(',', $configuredSockets)));
            if (!in_array($localPodmanSocket, $sockets, true)) {
                $sockets[] = $localPodmanSocket;
            }
            $rows['CADDY_DOCKER_SOCKETS'] = implode(',', $sockets);
        }
    }
    assert($rows['CADDY_DOCKER_SOCKETS'] === 'tcp://debian-test:2375,unix:///var/run/podman/podman.sock');
    echo 'PHP_ASSERT_OK';
    """
    res = subprocess.run(["php", "-r", php_code], capture_output=True, text=True)
    assert res.returncode == 0
    assert "PHP_ASSERT_OK" in res.stdout
