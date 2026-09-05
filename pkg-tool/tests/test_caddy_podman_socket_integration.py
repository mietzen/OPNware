import os
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
    assert "podman-dockerproxy-indicator" in volt_view
    assert "podman_socket_active" in volt_view
    assert "unix:///var/run/podman/podman.sock" in volt_view


def test_dockerproxy_script_direct_execution():
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        env_file = tmp_path / "env"
        env_file.write_text("CUSTOM_VAR=hello\n")

        mock_config_inc = tmp_path / "config.inc"
        mock_config_inc.write_text("""<?php
namespace OPNsense\\Core;
class Config {
    private static $instance;
    public static function getInstance() {
        if (!self::$instance) { self::$instance = new self(); }
        return self::$instance;
    }
    public function object() {
        $obj = new \\stdClass();
        $obj->OPNsense = new \\stdClass();
        $obj->OPNsense->caddyadvanced = new \\stdClass();
        $obj->OPNsense->caddyadvanced->general = new \\stdClass();
        $obj->OPNsense->caddyadvanced->general->EnvFile = getenv('TEST_ENVFILE');
        $obj->OPNsense->caddyadvanced->dockerproxy = new \\stdClass();
        $obj->OPNsense->caddyadvanced->dockerproxy->enabled = '1';
        $obj->OPNsense->caddyadvanced->dockerproxy->docker_sockets = getenv('TEST_SOCKETS') ?: '';
        return $obj;
    }
}
""")

        script_dir = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced").resolve()
        test_wrapper = tmp_path / "run_test.php"
        test_wrapper.write_text(f"""<?php
set_include_path('{tmp_path}' . PATH_SEPARATOR . '{script_dir}');
require '{script_dir}/dockerproxy.php';
""")

        # Test 1: With custom sockets
        env = os.environ.copy()
        env["TEST_ENVFILE"] = str(env_file)
        env["TEST_SOCKETS"] = "tcp://remote-host:2375"
        res = subprocess.run(["php", str(test_wrapper)], env=env, capture_output=True, text=True)
        assert res.returncode == 0
        assert "OK" in res.stdout
        assert "CUSTOM_VAR=hello" in env_file.read_text()
        assert "CADDY_DOCKER_SOCKETS=tcp://remote-host:2375" in env_file.read_text()

        # Test 2: Auto-injection when podman is present
        podman_test_wrapper = tmp_path / "run_podman_test.php"
        podman_test_wrapper.write_text(f"""<?php
set_include_path('{tmp_path}' . PATH_SEPARATOR . '{script_dir}');
$hasPodman = true;
require '{script_dir}/dockerproxy.php';
""")
        env["TEST_SOCKETS"] = "tcp://docker-proxy-host:2375"
        res2 = subprocess.run(["php", str(podman_test_wrapper)], env=env, capture_output=True, text=True)
        assert res2.returncode == 0
        assert "unix:///var/run/podman/podman.sock" in env_file.read_text()
