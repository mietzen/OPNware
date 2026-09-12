"""
Unit tests for os-docker OPNsense plugin packaging, configuration, and backend integrity.
"""

from pathlib import Path
import configparser
import xml.etree.ElementTree as ET
import yaml
from pkg_tool import _load_spec

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DOCKER_PKG_DIR = REPO_ROOT / "pkgs" / "os-docker"


def test_docker_config_spec_valid():
    """Verify pkgs/os-docker/config.yml is valid and has correct metadata."""
    config_file = DOCKER_PKG_DIR / "config.yml"
    assert config_file.is_file()
    spec = _load_spec(str(config_file))

    assert spec["pkg_manifest"]["name"] == "docker"
    assert spec["pkg_manifest"]["origin"] == "opnware/os-docker"
    assert spec["plugin"]["opnsense_version"] == "26.7"
    assert "docker-cli" in spec["pkg_manifest"]["deps"]
    assert "vm-bhyve" in spec["pkg_manifest"]["deps"]
    assert "bhyve-firmware" in spec["pkg_manifest"]["deps"]
    assert spec["alpine"]["branch"] == "v3.24"
    assert spec["alpine"]["version"] == "3.24.1"


def test_docker_model_xml_schema():
    """Verify Docker.xml model has valid mount point and required fields."""
    model_xml = DOCKER_PKG_DIR / "src" / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Docker" / "Docker.xml"
    assert model_xml.is_file()
    tree = ET.parse(model_xml)
    root = tree.getroot()

    assert root.findtext("mount") == "//OPNsense/docker"
    general = root.find("items/general")
    assert general is not None
    assert general.find("enabled") is not None
    assert general.find("cpus") is not None
    assert general.find("memory") is not None
    assert general.find("disk_size") is not None
    assert general.find("interfaces") is not None
    assert general.find("subnet") is not None
    assert general.find("port_sync") is not None
    assert general.find("fail_on_conflict") is not None


def test_docker_form_xml_mapping():
    """Verify general.xml form field IDs map exactly to model items."""
    form_xml = DOCKER_PKG_DIR / "src" / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Docker" / "forms" / "general.xml"
    assert form_xml.is_file()
    tree = ET.parse(form_xml)
    root = tree.getroot()

    field_ids = [field.findtext("id") for field in root.findall("field")]
    expected_fields = [
        "docker.general.enabled",
        "docker.general.cpus",
        "docker.general.memory",
        "docker.general.disk_size",
        "docker.general.subnet",
        "docker.general.interfaces",
        "docker.general.port_sync",
        "docker.general.fail_on_conflict",
        "docker.general.log_level"
    ]
    for ef in expected_fields:
        assert ef in field_ids, f"Field {ef} missing in form XML"


def test_docker_configd_actions():
    """Verify actions_docker.conf syntax and command declarations."""
    actions_file = DOCKER_PKG_DIR / "src" / "opnsense" / "service" / "conf" / "actions.d" / "actions_docker.conf"
    assert actions_file.is_file()

    parser = configparser.ConfigParser()
    parser.read(actions_file)

    required_actions = [
        "start", "stop", "restart", "status", "setup", "host_resources",
        "containers_list", "containers_start", "containers_stop", "containers_restart",
        "containers_delete", "containers_logs", "containers_inspect",
        "images_list", "images_pull", "images_delete", "images_prune",
        "volumes_list", "volumes_create", "volumes_inspect", "volumes_delete", "volumes_prune",
        "networks_list", "networks_inspect", "networks_delete",
        "system_stats", "system_info", "system_df", "system_prune"
    ]

    for act in required_actions:
        assert parser.has_section(act), f"Missing configd action section: {act}"
        assert parser.has_option(act, "command"), f"Action {act} missing command"
        assert parser.has_option(act, "type"), f"Action {act} missing type"


def test_docker_templates_and_targets():
    """Verify +TARGETS template destinations."""
    targets_file = DOCKER_PKG_DIR / "src" / "opnsense" / "service" / "templates" / "OPNsense" / "Docker" / "+TARGETS"
    assert targets_file.is_file()

    targets_text = targets_file.read_text()
    assert "rc.conf.d/docker:/etc/rc.conf.d/docker" in targets_text
    assert "docker-vm.conf:/var/db/vm/docker-vm/docker-vm.conf" in targets_text


def test_alpine_update_detection(monkeypatch):
    """Verify Alpine release update detection logic."""
    from pkg_tool import _alpine_latest_version

    sample_yaml = """
- flavor: alpine-virt
  version: "3.24.2"
- flavor: alpine-standard
  version: "3.24.2"
"""
    class MockResponse:
        status_code = 200
        text = sample_yaml

    monkeypatch.setattr("requests.get", lambda url, timeout=10: MockResponse())
    ver = _alpine_latest_version("v3.24")
    assert ver == "3.24.2"


def test_package_file_overlap_coexistence():
    """Verify that no packages have overlapping file paths in src/ (pkg conflicts)."""
    import os
    from collections import defaultdict

    pkgs_dir = REPO_ROOT / "pkgs"
    file_owners = defaultdict(list)
    for pkg in os.listdir(pkgs_dir):
        src = pkgs_dir / pkg / "src"
        if src.is_dir():
            for root, _, files in os.walk(src):
                for f in files:
                    rel_path = os.path.relpath(os.path.join(root, f), src)
                    file_owners[rel_path].append(pkg)

    conflicts = {path: owners for path, owners in file_owners.items() if len(owners) > 1}
    assert not conflicts, f"Conflicting files found between packages: {conflicts}"


def test_docker_acl_and_log_routes():
    """Verify ACL includes service UI, API, and Diagnostics log routes."""
    acl_file = DOCKER_PKG_DIR / "src" / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Docker" / "ACL" / "ACL.xml"
    assert acl_file.is_file()
    tree = ET.parse(acl_file)
    patterns = [p.text for p in tree.getroot().findall(".//pattern")]

    assert "ui/docker/*" in patterns
    assert "api/docker/*" in patterns
    assert "ui/diagnostics/log/core/docker*" in patterns
    assert "api/diagnostics/log/core/docker*" in patterns


def test_docker_dashboard_tabs_and_terminal():
    """Verify dashboard.volt contains all required tabs, terminal wiring, and handlers."""
    dash_file = DOCKER_PKG_DIR / "src" / "opnsense" / "mvc" / "app" / "views" / "OPNsense" / "Docker" / "dashboard.volt"
    assert dash_file.is_file()
    content = dash_file.read_text()

    assert "#tab-containers" in content
    assert "#tab-images" in content
    assert "#tab-volumes" in content
    assert "#tab-networks" in content
    assert "cli-shell" in content
    assert "btn_clear_cli" in content
    assert "$('#btn_clear_cli').click" in content
    assert "$('#cli-shell').change" in content
    assert "resize.terminal" in content
    assert "stat-reclaimable" in content


def test_docker_syslog_config():
    """Verify syslog-ng fragment captures all docker logs including terminal and dockerd."""
    conf_file = DOCKER_PKG_DIR / "src" / "etc" / "syslog-ng.conf.d" / "docker.conf"
    assert conf_file.is_file()
    text = conf_file.read_text()

    assert "/var/log/docker/setup.log" in text
    assert "/var/log/docker/port_sync.log" in text
    assert "/var/log/docker/terminal.log" in text
    assert "/var/log/docker/dockerd.log" in text
    assert "d_local_docker" in text


def test_docker_port_sync_interface_logic(tmp_path, monkeypatch):
    """Verify docker_port_sync.py reads configured interfaces from config.xml."""
    import importlib.util
    sync_script = DOCKER_PKG_DIR / "src" / "opnsense" / "scripts" / "OPNsense" / "Docker" / "docker_port_sync.py"
    spec = importlib.util.spec_from_file_location("docker_port_sync", str(sync_script))
    docker_port_sync = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(docker_port_sync)

    config_xml = """<opnsense>
        <interfaces>
            <lan><if>vtnet0</if></lan>
            <opt1><if>vtnet2</if></opt1>
        </interfaces>
        <OPNsense>
            <docker>
                <general>
                    <interfaces>lan,opt1</interfaces>
                </general>
            </docker>
        </OPNsense>
    </opnsense>"""
    cfg_file = tmp_path / "config.xml"
    cfg_file.write_text(config_xml)

    ifs = docker_port_sync.get_configured_interfaces(config_path=str(cfg_file))
    assert "lo0" in ifs
    assert "vtnet0" in ifs
    assert "vtnet2" in ifs


def test_docker_api_controller_rest_and_cache():
    """Verify DockerApiControllerBase and controllers implement direct REST methods and df cache."""
    base_file = DOCKER_PKG_DIR / "src" / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Docker" / "Api" / "DockerApiControllerBase.php"
    assert base_file.is_file()
    base_content = base_file.read_text()

    assert "DOCKER_REST_BASE" in base_content
    assert "dockerRest" in base_content
    assert "executeRestQuery" in base_content
    assert "executeRestAction" in base_content
    assert "stripDockerLogHeaders" in base_content
    assert "DF_CACHE_FILE" in base_content
    assert "invalidateDfCache" in base_content

    sys_file = DOCKER_PKG_DIR / "src" / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Docker" / "Api" / "SystemController.php"
    assert sys_file.is_file()
    sys_content = sys_file.read_text()

    assert "DF_CACHE_TTL" in sys_content
    assert "executeAction('system_stats')" in sys_content


def test_docker_port_sync_rest_parsing(monkeypatch):
    """Verify docker_port_sync.py parses Docker REST API container port mappings."""
    import importlib.util
    import io
    sync_script = DOCKER_PKG_DIR / "src" / "opnsense" / "scripts" / "OPNsense" / "Docker" / "docker_port_sync.py"
    spec = importlib.util.spec_from_file_location("docker_port_sync", str(sync_script))
    docker_port_sync = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(docker_port_sync)

    mock_response_data = [
        {
            "Id": "1234567890ab",
            "Names": ["/my-web"],
            "Ports": [
                {"PrivatePort": 80, "PublicPort": 8080, "Type": "tcp"},
                {"PrivatePort": 53, "PublicPort": 53, "Type": "udp"}
            ]
        }
    ]

    class MockHTTPResponse:
        def __init__(self, data):
            import json
            self._bytes = json.dumps(data).encode("utf-8")
        def read(self):
            return self._bytes
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass

    monkeypatch.setattr(
        docker_port_sync.urllib.request,
        "urlopen",
        lambda req, timeout=2: MockHTTPResponse(mock_response_data)
    )

    ports = docker_port_sync.get_container_published_ports()
    assert len(ports) == 2
    assert ports[0]["container"] == "my-web"
    assert ports[0]["host_port"] == 8080
    assert ports[0]["container_port"] == 80
    assert ports[0]["proto"] == "tcp"
    assert ports[1]["proto"] == "udp"


def test_docker_base_image_daemon_json():
    """Verify build_base_image.sh and build_alpine_vm.py configure containerd-snapshotter false."""
    script_file = DOCKER_PKG_DIR / "scripts" / "build_base_image.sh"
    assert script_file.is_file()
    content = script_file.read_text()
    assert "containerd-snapshotter" in content
    assert "false" in content

    vm_script = DOCKER_PKG_DIR / "scripts" / "build_alpine_vm.py"
    assert vm_script.is_file()
    vm_content = vm_script.read_text()
    assert "containerd-snapshotter" in vm_content
def test_docker_socket_proxy_and_min_disk():
    """Verify socat dependency, MinimumValue 2 for disk, and rc.d/docker socket forwarding."""
    config_yml = DOCKER_PKG_DIR / "config.yml"
    assert config_yml.is_file()
    import yaml
    cfg = yaml.safe_load(config_yml.read_text())
    assert "socat" in cfg["pkg_manifest"]["deps"]
    assert cfg["pkg_manifest"]["deps"]["socat"]["origin"] == "net/socat"

    model_xml = DOCKER_PKG_DIR / "src" / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Docker" / "Docker.xml"
    tree = ET.parse(model_xml)
    min_disk = tree.findtext("items/general/disk_size/MinimumValue")
    assert min_disk == "2"

    rc_file = DOCKER_PKG_DIR / "src" / "usr" / "local" / "etc" / "rc.d" / "docker"
    rc_content = rc_file.read_text()
    assert "socat" in rc_content
    assert "/var/run/docker.sock" in rc_content
    assert "UNIX-LISTEN:/var/run/docker.sock" in rc_content


def test_docker_firewall_isolation():
    """Verify docker.inc does not expose broad unauthenticated subnet access."""
    inc_file = DOCKER_PKG_DIR / "src" / "etc" / "inc" / "plugins.inc.d" / "docker.inc"
    assert inc_file.is_file()
    content = inc_file.read_text()
    assert "opnware-docker/*" in content
    # Ensure wide open pass rule to entire subnet from any interface is removed
    assert "Allow access to Docker container published ports on" not in content


def test_terminal_daemon_origin_validation():
    """Verify terminal_daemon.py validates Origin header to prevent CSWSH."""
    daemon_file = DOCKER_PKG_DIR / "src" / "opnsense" / "scripts" / "OPNsense" / "Docker" / "terminal_daemon.py"
    assert daemon_file.is_file()
    content = daemon_file.read_text()
    assert "is_valid_origin" in content


def test_docker_api_controller_fast_abort():
    """Verify DockerApiControllerBase avoids cascading 60s fallback when MicroVM is unreachable."""
    ctrl_file = DOCKER_PKG_DIR / "src" / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Docker" / "Api" / "DockerApiControllerBase.php"
    assert ctrl_file.is_file()
    content = ctrl_file.read_text()
    assert "code === 0" in content or "curl_errno" in content or "$res['code'] === 0" in content


def test_docker_rc_readiness_wait():
    """Verify rc.d/docker waits for microVM TCP 2375 readiness on startup."""
    rc_file = DOCKER_PKG_DIR / "src" / "usr" / "local" / "etc" / "rc.d" / "docker"
    assert rc_file.is_file()
    content = rc_file.read_text()
    assert "Waiting for Docker daemon readiness" in content or "100.64.0.2 2375" in content


def test_docker_setup_disk_shrink_protection():
    """Verify setup.php does not automatically unlink data.img on shrink."""
    setup_file = DOCKER_PKG_DIR / "src" / "opnsense" / "scripts" / "OPNsense" / "Docker" / "setup.php"
    assert setup_file.is_file()
    content = setup_file.read_text()
    assert "@unlink($dataImgTarget)" not in content


def test_docker_api_controller_session_lock_release():
    """Verify DockerApiControllerBase releases session write lock to allow parallel requests."""
    ctrl_file = DOCKER_PKG_DIR / "src" / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Docker" / "Api" / "DockerApiControllerBase.php"
    assert ctrl_file.is_file()
    content = ctrl_file.read_text()
    assert "session_write_close" in content

