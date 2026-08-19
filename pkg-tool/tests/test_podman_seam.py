"""Tests for Podman package redistribution and os-podman plugin structure."""

from pathlib import Path
from pkg_tool import _load_spec

ROOT_DIR = Path(__file__).resolve().parents[2]
PKGS_DIR = ROOT_DIR / "pkgs"

REDISTRIBUTE_PKGS = [
    "podman",
    "conmon",
    "containernetworking-plugins",
    "containers-common",
    "gpgme",
    "ocijail",
]


def test_podman_redistribute_specs_valid():
    for name in REDISTRIBUTE_PKGS:
        config_path = PKGS_DIR / name / "config.yml"
        assert config_path.exists(), f"{name}/config.yml missing"
        spec = _load_spec(str(config_path))
        redist = spec.get("redistribute")
        assert redist, f"{name}/config.yml missing redistribute section"
        assert redist["name"] == name
        assert "FreeBSD-15-amd64" in redist["version"]
        assert redist["repo"] == "http://pkg.freebsd.org"
        assert redist["path"] == "quarterly/All"

        build_sh = PKGS_DIR / name / "build.sh"
        assert build_sh.exists()
        assert build_sh.stat().st_mode & 0o111, f"{name}/build.sh not executable"


def test_os_podman_spec_and_files_valid():
    podman_dir = PKGS_DIR / "os-podman"
    assert podman_dir.exists()

    spec = _load_spec(str(podman_dir / "config.yml"))
    manifest = spec.get("pkg_manifest", {})
    assert manifest.get("name") == "podman"
    assert manifest.get("origin") == "opnware/os-podman"
    assert manifest.get("version") == "0.1.10"

    deps = manifest.get("deps", {})
    for name in REDISTRIBUTE_PKGS:
        assert name in deps, f"os-podman missing dependency on {name}"

    # Check key files
    src = podman_dir / "src"
    inc_content = (src / "etc" / "inc" / "plugins.inc.d" / "podman.inc").read_text()
    assert "/var/run/podman/podman_service.pid" in inc_content
    assert "function podman_firewall" in inc_content
    assert "cni-rdr/*" in inc_content
    assert "registerSNatRule" in inc_content
    assert "Allow outbound traffic from Podman container networks" in inc_content

    assert (src / "etc" / "syslog-ng.conf.d" / "podman.conf").exists()
    assert (src / "usr" / "local" / "etc" / "rc.d" / "podman-service").exists()
    assert (src / "opnsense" / "service" / "conf" / "actions.d" / "actions_podman.conf").exists()
    assert (src / "opnsense" / "service" / "templates" / "OPNsense" / "Podman" / "+TARGETS").exists()

    podman_xml = (src / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Podman" / "Podman.xml").read_text()
    assert "<interfaces" in podman_xml
    assert (src / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Podman" / "Podman.php").exists()

    menu_content = (src / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Podman" / "Menu" / "Menu.xml").read_text()
    assert "<menu>" in menu_content
    assert "/ui/diagnostics/log/core/podman" in menu_content

    acl_content = (src / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Podman" / "ACL" / "ACL.xml").read_text()
    assert "ui/diagnostics/log/core/podman" in acl_content

    forms_general = (src / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Podman" / "forms" / "general.xml").read_text()
    assert "podman.general.interfaces" in forms_general

    general_volt = (src / "opnsense" / "mvc" / "app" / "views" / "OPNsense" / "Podman" / "general.volt").read_text()
    assert "'frm_general': '/api/podman/general/get'" in general_volt
    assert "tbl_podman_status" in general_volt
    assert "updateStatus()" in general_volt
    assert "updateRemoteGuide" in general_volt

    dashboard_content = (src / "opnsense" / "mvc" / "app" / "views" / "OPNsense" / "Podman" / "dashboard.volt").read_text()
    assert "btn_refresh_containers" not in dashboard_content
    assert "modal-logs" in dashboard_content
    assert "modal-inspect" in dashboard_content
    assert "modal-cli" in dashboard_content
    assert "btn-cli-stop" in dashboard_content
    assert "stopContainerCli" in dashboard_content
    cli_modal_section = dashboard_content[dashboard_content.find('id="modal-cli"'):]
    assert 'class="modal-footer"' not in cli_modal_section
    assert "ansiToHtml" in dashboard_content
    assert "act-cli" in dashboard_content
    assert "btn_system_prune" in dashboard_content
    assert "formatTimestamp" in dashboard_content

    assert (src / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Podman" / "Api" / "PodmanApiControllerBase.php").exists()

    containers_ctrl = (src / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Podman" / "Api" / "ContainersController.php").read_text()
    assert "extends PodmanApiControllerBase" in containers_ctrl
    assert "public function deleteAction" in containers_ctrl
    assert "public function logsAction" in containers_ctrl
    assert "public function inspectAction" in containers_ctrl
    assert "public function execAction" in containers_ctrl

    system_ctrl = (src / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Podman" / "Api" / "SystemController.php").read_text()
    assert "public function statusAction" in system_ctrl

    setup_content = (src / "opnsense" / "scripts" / "OPNsense" / "Podman" / "setup.php").read_text()
    assert "kern.elf64.fallback_brand=3" in setup_content
    assert "kern.racct.enable" in setup_content

    manage_content = (src / "opnsense" / "scripts" / "OPNsense" / "Podman" / "manage.py").read_text()
    assert "containers.exec" in manage_content

    assert (ROOT_DIR / "docs" / "plugins" / "os-podman.md").exists()
