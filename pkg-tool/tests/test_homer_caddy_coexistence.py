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
    assert "if (homer_caddy_is_present()) {" in src


def test_homer_rcd_skips_when_caddy_advanced_present():
    src = HOMER_RCD.read_text()
    assert "/usr/local/opnsense/version/caddy-advanced" in src
    assert "Homer is managed by Caddy Advanced via conf.d/homer.caddy" in src


def test_homer_sync_caddy_script():
    assert HOMER_SYNC.is_file()
    src = HOMER_SYNC.read_text()
    assert "homer_caddy_is_present" in src
    assert "/usr/local/etc/caddy/conf.d/homer.caddy" in src
    assert "service homer stop" in src
    assert "configctl caddyadvanced reload" in src


def test_homer_general_controller_caddy_sync_and_gate():
    src = HOMER_GENERAL_CTRL.read_text()
    assert "parseCaddyConf" in src
    assert "caddy_managed" in src
    assert "homer_caddy_is_present()" in src
    assert "Settings are managed by Caddy Advanced via /usr/local/etc/caddy/conf.d/homer.caddy" in src


def test_homer_service_controller_status_and_reconfigure():
    src = HOMER_SERVICE_CTRL.read_text()
    assert "homer_caddy_is_present()" in src
    assert "caddyadvanced status" in src
    assert "homer sync-caddy" in src


def test_homer_general_volt_read_only_and_alert():
    src = HOMER_GENERAL_VOLT.read_text()
    assert 'id="alert-caddy-managed"' in src
    assert "Managed by Caddy Advanced" in src
    assert "data.caddy_managed" in src
    assert "running (Caddy Advanced)" in src


def test_homer_action_sync_caddy_registered():
    src = HOMER_ACTIONS.read_text()
    assert "[sync-caddy]" in src
    assert "sync_caddy.php" in src


def test_homer_pkg_trigger():
    assert HOMER_TRIGGER.is_file()
    src = HOMER_TRIGGER.read_text()
    assert 'path: "/usr/local/opnsense/version"' in src
    assert "sync_caddy.php" in src


def test_caddy_setup_and_editor_seed_homer():
    setup_src = CADDY_SETUP.read_text()
    assert "sync_caddy.php" in setup_src
    editor_src = CADDY_EDITOR.read_text()
    assert "conf.d/homer.caddy" in editor_src


def test_package_versions_bumped():
    homer_spec = yaml.safe_load(HOMER_CONFIG.read_text())
    assert homer_spec["pkg_manifest"]["version"] == "0.5.10"

    caddy_spec = yaml.safe_load(CADDY_CONFIG.read_text())
    assert caddy_spec["pkg_manifest"]["version"] == "0.8.17"
