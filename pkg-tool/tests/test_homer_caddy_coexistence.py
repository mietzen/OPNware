"""Source-seam tests for os-caddy and os-homer coexistence and single caddy daemon."""

from pathlib import Path
import yaml

HOMER_INC = Path("pkgs/os-homer/src/etc/inc/plugins.inc.d/homer.inc")
HOMER_RCD = Path("pkgs/os-homer/src/usr/local/etc/rc.d/homer")
HOMER_SYNC = Path("pkgs/os-homer/src/opnsense/scripts/OPNsense/Homer/sync_caddy.php")
HOMER_GENERAL_CTRL = Path("pkgs/os-homer/src/opnsense/mvc/app/controllers/OPNsense/Homer/Api/GeneralController.php")
HOMER_SERVICE_CTRL = Path("pkgs/os-homer/src/opnsense/mvc/app/controllers/OPNsense/Homer/Api/ServiceController.php")
HOMER_GENERAL_VOLT = Path("pkgs/os-homer/src/opnsense/mvc/app/views/OPNsense/Homer/general.volt")
HOMER_ACTIONS = Path("pkgs/os-homer/src/opnsense/service/conf/actions.d/actions_homer.conf")
HOMER_TRIGGER = Path("pkgs/os-homer/src/share/pkg/triggers/os-homer-caddy.ucl")
HOMER_CONFIG = Path("pkgs/os-homer/config.yml")
CADDY_CONFIG = Path("pkgs/os-caddy-advanced/config.yml")
CADDY_SETUP = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/setup.php")
CADDY_EDITOR = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/editor_tree.php")


def test_homer_inc_presence_and_services_gate():
    src = HOMER_INC.read_text()
    assert "function homer_caddy_is_present()" in src
    assert "file_exists('/usr/local/opnsense/version/caddy-advanced')" in src
    assert "function homer_configure()" in src
    assert "'local' => ['homer_caddy_sync']" in src
    assert "configdRun('homer sync-caddy')" in src
    assert "function homer_services()" in src


def test_homer_rcd_skips_when_caddy_advanced_present():
    src = HOMER_RCD.read_text()
    assert "/usr/local/opnsense/version/caddy-advanced" in src
    assert "Homer is managed by Caddy Advanced via conf.d/homer.caddy" in src


def test_homer_sync_caddy_script():
    assert HOMER_SYNC.is_file()
    src = HOMER_SYNC.read_text()
    assert "homer_caddy_is_present" in src
    assert "/usr/local/etc/caddy/conf.d/homer.caddy" in src
    assert "service homer onestop" in src
    assert "version/homer" in src
    assert "service caddy reload" in src


def test_homer_general_controller_caddy_sync_and_gate():
    src = HOMER_GENERAL_CTRL.read_text()
    assert "getCaddyManagedConfig" in src
    assert "caddy_managed" in src
    assert "homer_caddy_is_present()" in src
    assert "Settings are managed by Caddy Advanced via /usr/local/etc/caddy/conf.d/homer.caddy" in src


def test_homer_service_controller_status_contract():
    src = HOMER_SERVICE_CTRL.read_text()
    assert "homer_caddy_is_present()" in src
    assert "conf.d/homer.caddy" in src
    assert "caddyadvanced status" in src
    assert "'status' => 'disabled'" in src
    assert "'running' => $homerRunning" in src
    assert "function reconfigureAction" in src
    assert "homer sync-caddy" in src


def test_homer_general_volt_read_only_and_alert():
    src = HOMER_GENERAL_VOLT.read_text()
    assert 'id="alert-caddy-managed"' in src
    assert "Managed by Caddy Advanced" in src
    assert "caddyManaged" in src
    assert "$.getJSON(\"/api/homer/service/status\"" in src


def test_homer_action_sync_caddy_registered():
    src = HOMER_ACTIONS.read_text()
    assert "[sync-caddy]" in src
    assert "sync_caddy.php" in src
    assert "type:script\n" in src


def test_homer_pkg_trigger_has_install_and_cleanup():
    assert HOMER_TRIGGER.is_file()
    src = HOMER_TRIGGER.read_text()
    assert 'path: "/usr/local/opnsense/version"' in src
    assert "cleanup:" in src
    assert "trigger:" in src
    assert "sync_caddy.php" in src


def test_homer_model_caddy_managed_config_functional(tmp_path):
    import subprocess
    import json

    model_path = Path("pkgs/os-homer/src/opnsense/mvc/app/models/OPNsense/Homer/Homer.php").resolve()
    test_script = tmp_path / "runner.php"

    test_script.write_text(f"""<?php
namespace OPNsense\\Base {{ class BaseModel {{}} }}
namespace {{
    require_once '{model_path}';
    $mdl = new OPNsense\\Homer\\Homer();
    $cases = [
        'default_tls' => ":9443 {{\\n\\troot * /usr/local/www/homer\\n\\tfile_server\\n\\ttls internal {{\\n\\t\\ton_demand\\n\\t}}\\n}}\\n",
        'hostname_custom_port' => "homer.test.lan:8080 {{\\n\\troot * /usr/local/www/homer\\n\\tfile_server\\n}}\\n",
        'localhost_port' => "127.0.0.1:9090 {{\\n\\troot * /usr/local/www/homer\\n\\tfile_server\\n}}\\n",
        'ipv6_bracket' => "[2001:db8::1]:9443 {{\\n\\troot * /usr/local/www/homer\\n\\tfile_server\\n\\ttls internal\\n}}\\n",
        'lan_ip' => "192.168.1.1:8443 {{\\n\\troot * /usr/local/www/homer\\n\\tfile_server\\n}}\\n",
        'https_schema' => "https://homer.test.lan:8443 {{\\n\\troot * /usr/local/www/homer\\n\\tfile_server\\n}}\\n",
        'domain_auto_https' => "homer.internal.lan {{\\n\\troot * /usr/local/www/homer\\n\\tfile_server\\n}}\\n",
    ];
    $results = [];
    foreach ($cases as $name => $content) {{
        $f = '{tmp_path}/' . $name . '.caddy';
        file_put_contents($f, $content);
        $results[$name] = $mdl->getCaddyManagedConfig($f);
    }}
    echo json_encode($results);
}}
""")

    res = subprocess.run(["php", str(test_script)], capture_output=True, text=True, check=True)
    parsed = json.loads(res.stdout)

    assert parsed["default_tls"]["Port"] == "9443"
    assert parsed["default_tls"]["Interface"] == "all"
    assert parsed["default_tls"]["ServerName"] == ""
    assert parsed["default_tls"]["TlsEnabled"] == "1"
    assert parsed["default_tls"]["enabled"] == "1"

    assert parsed["hostname_custom_port"]["Port"] == "8080"
    assert parsed["hostname_custom_port"]["Interface"] == "all"
    assert parsed["hostname_custom_port"]["ServerName"] == "homer.test.lan"
    assert parsed["hostname_custom_port"]["TlsEnabled"] == "0"

    assert parsed["localhost_port"]["Port"] == "9090"
    assert parsed["localhost_port"]["Interface"] == "localhost"
    assert parsed["localhost_port"]["ServerName"] == ""

    assert parsed["ipv6_bracket"]["Port"] == "9443"
    assert parsed["ipv6_bracket"]["Interface"] == "lan"
    assert parsed["ipv6_bracket"]["ServerName"] == ""
    assert parsed["ipv6_bracket"]["TlsEnabled"] == "1"

    assert parsed["lan_ip"]["Port"] == "8443"
    assert parsed["lan_ip"]["Interface"] == "lan"
    assert parsed["lan_ip"]["ServerName"] == ""

    assert parsed["https_schema"]["Port"] == "8443"
    assert parsed["https_schema"]["Interface"] == "all"
    assert parsed["https_schema"]["ServerName"] == "homer.test.lan"
    assert parsed["https_schema"]["TlsEnabled"] == "1"

    assert parsed["domain_auto_https"]["Port"] == "443"
    assert parsed["domain_auto_https"]["Interface"] == "all"
    assert parsed["domain_auto_https"]["ServerName"] == "homer.internal.lan"
    assert parsed["domain_auto_https"]["TlsEnabled"] == "1"


CADDY_SERVICE_CTRL = Path("pkgs/os-caddy-advanced/src/opnsense/mvc/app/controllers/OPNsense/CaddyAdvanced/Api/ServiceController.php")


def test_caddy_reconfigure_triggers_homer_sync():
    src = CADDY_SERVICE_CTRL.read_text()
    assert "homer sync-caddy" in src


def test_homer_rcd_checks_caddy_enable():
    src = HOMER_RCD.read_text()
    assert ". /etc/rc.conf.d/caddy" in src
    assert '[ "${caddy_enable}" = "YES" ]' in src
    assert 'start_precmd="homer_prestart"' in src


def test_package_versions_bumped():
    homer_spec = yaml.safe_load(HOMER_CONFIG.read_text())
    assert homer_spec["pkg_manifest"]["version"] == "0.5.10"

    caddy_spec = yaml.safe_load(CADDY_CONFIG.read_text())
    assert caddy_spec["pkg_manifest"]["version"] == "0.8.17"


CADDY_RCD = Path("pkgs/os-caddy-advanced/src/usr/local/etc/rc.d/caddy")
CADDY_HOMER_TRIGGER = Path("pkgs/os-caddy-advanced/src/share/pkg/triggers/os-caddy-advanced-homer.ucl")


def test_caddy_rcd_precmd_stops_homer():
    src = CADDY_RCD.read_text()
    assert "/usr/local/etc/rc.d/homer" in src
    assert "service homer onestop" in src
    assert "/usr/local/etc/os-homer/Caddyfile" in src


def test_caddy_homer_trigger_bidirectional():
    assert CADDY_HOMER_TRIGGER.is_file()
    src = CADDY_HOMER_TRIGGER.read_text()
    assert 'path: "/usr/local/opnsense/version"' in src
    assert "cleanup: {" in src
    assert "trigger: {" in src
    assert "sync_caddy.php" in src
    assert "conf.d/homer.caddy" in src
    assert '"/usr/sbin/service", "caddy", "reload"' in src


def test_homer_sync_caddy_preserves_existing():
    src = HOMER_SYNC.read_text()
    assert "!file_exists(CADDY_HOMER_FILE)" in src
    assert "file_put_contents(CADDY_HOMER_FILE, $content)" in src
    assert "$managed = $mdl->getCaddyManagedConfig();" in src
    assert "unlink(CADDY_HOMER_FILE)" in src


def test_homer_model_parses_custom_caddyfile(tmp_path):
    import subprocess
    import json

    model_path = Path("pkgs/os-homer/src/opnsense/mvc/app/models/OPNsense/Homer/Homer.php").resolve()
    test_script = tmp_path / "custom_runner.php"

    conf_custom = tmp_path / "homer.caddy"
    conf_custom.write_text("homer.custom.lan:8085 {\n\troot * /usr/local/www/homer\n\tfile_server\n\ttls internal\n}\n")

    test_script.write_text(f"""<?php
namespace OPNsense\\Base {{ class BaseModel {{}} }}
namespace {{
    require_once '{model_path}';
    $mdl = new OPNsense\\Homer\\Homer();
    $res = $mdl->getCaddyManagedConfig('{tmp_path}/homer.caddy');
    echo json_encode($res);
}}
""")

    res = subprocess.run(["php", str(test_script)], capture_output=True, text=True, check=True)
    parsed = json.loads(res.stdout)

    assert parsed["enabled"] == "1"
    assert parsed["Port"] == "8085"
    assert parsed["ServerName"] == "homer.custom.lan"
    assert parsed["TlsEnabled"] == "1"
