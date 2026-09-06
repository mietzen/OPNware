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
    assert manifest.get("version") == "0.1.27"

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

    syslog_conf = (src / "etc" / "syslog-ng.conf.d" / "podman.conf").read_text()
    assert "junction {" in syslog_conf
    assert "kv-parser(prefix(\".podman.\"))" in syslog_conf
    assert "set-severity(\"7\" condition(match(\"debug\" value(\".podman.level\"))))" in syslog_conf
    assert "set-severity(\"3\" condition(match(\"error\" value(\".podman.level\"))))" in syslog_conf
    assert "set(\"${.podman.msg}\" value(\"MESSAGE\")" in syslog_conf
    rc_content = (src / "usr" / "local" / "etc" / "rc.d" / "podman-service").read_text()
    assert "-r -R 1" in rc_content
    assert "podman_service_sup.pid" in rc_content
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
    assert "selectGuideTab" in general_volt
    assert "Note on SSH Access & Root Privileges" in general_volt

    dashboard_content = (src / "opnsense" / "mvc" / "app" / "views" / "OPNsense" / "Podman" / "dashboard.volt").read_text()
    assert "btn_refresh_containers" not in dashboard_content
    assert "modal-logs" in dashboard_content
    assert "modal-inspect" in dashboard_content
    assert "modal-cli" in dashboard_content
    assert "xterm-terminal-container" in dashboard_content
    assert "connectTerminalWs" in dashboard_content
    cli_modal_section = dashboard_content[dashboard_content.find('id="modal-cli"'):]
    assert 'class="modal-footer"' in cli_modal_section
    assert "ansiToHtml" in dashboard_content
    assert "act-cli" in dashboard_content
    assert (src / "opnsense" / "www" / "js" / "widgets" / "Podman.js").exists()
    assert (src / "opnsense" / "www" / "js" / "widgets" / "Metadata" / "Podman.xml").exists()
    widget_js = (src / "opnsense" / "www" / "js" / "widgets" / "Podman.js").read_text()
    assert "class Podman extends BaseTableWidget" in widget_js
    assert "podmanContainersTable" in widget_js
    assert "/api/podman/containers/list" in widget_js
    widget_xml = (src / "opnsense" / "www" / "js" / "widgets" / "Metadata" / "Podman.xml").read_text()
    assert "<filename>Podman.js</filename>" in widget_xml
    assert "<title>Podman Containers</title>" in widget_xml

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
    assert "/usr/local/bin/docker" in setup_content
    assert "hasExistingStorage" in setup_content
    assert "skipping zroot/containers creation" in setup_content
    assert "BEGIN OPNWARE PODMAN ALIASES" in setup_content
    assert "profile.d/podman.sh" in setup_content
    assert "podman-wrapper" in setup_content
    assert "unqualified-search-registries" in setup_content

    # Stream A wrapper & build staging assertions
    wrapper_path = src / "usr" / "local" / "bin" / "podman-wrapper"
    assert wrapper_path.exists()
    assert wrapper_path.stat().st_mode & 0o111
    wrapper_text = wrapper_path.read_text()
    assert "--platform linux/amd64" in wrapper_text
    assert "build|run|create|pull" in wrapper_text

    build_sh_text = (podman_dir / "build.sh").read_text()
    assert "bin/podman-wrapper" in build_sh_text

    assert "<default_linux_platform" in podman_xml
    assert "<docker_alias" in podman_xml
    assert "<docker_search_registry" in podman_xml

    assert "podman.general.default_linux_platform" in forms_general
    assert "podman.general.docker_alias" in forms_general
    assert "podman.general.docker_search_registry" in forms_general

    manage_content = (src / "opnsense" / "scripts" / "OPNsense" / "Podman" / "manage.py").read_text()
    assert "containers.exec" in manage_content
    assert '"start", "--", param' in manage_content
    assert '"rm", "-f", "--", param' in manage_content
    assert "VALID_SHELLS" in manage_content

    api_base = (src / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Podman" / "Api" / "PodmanApiControllerBase.php").read_text()
    assert "isValidIdentifier" in api_base

    doc_text = (ROOT_DIR / "docs" / "plugins" / "os-podman.md").read_text()
    assert "Root Privileges Required" in doc_text
    assert (ROOT_DIR / "docs" / "plugins" / "os-podman.md").exists()

