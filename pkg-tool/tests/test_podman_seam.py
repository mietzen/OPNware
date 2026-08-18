"""Tests for Podman package redistribution and os-podman plugin structure."""

from pathlib import Path
from pkg_tool import _load_spec

PKGS_DIR = Path(__file__).resolve().parents[2] / "pkgs"

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

    deps = manifest.get("deps", {})
    for name in REDISTRIBUTE_PKGS:
        assert name in deps, f"os-podman missing dependency on {name}"

    # Check key files
    src = podman_dir / "src"
    assert (src / "etc" / "inc" / "plugins.inc.d" / "podman.inc").exists()
    assert (src / "etc" / "syslog-ng.conf.d" / "podman.conf").exists()
    assert (src / "usr" / "local" / "etc" / "rc.d" / "podman").exists()
    assert (src / "opnsense" / "service" / "conf" / "actions.d" / "actions_podman.conf").exists()
    assert (src / "opnsense" / "service" / "templates" / "OPNsense" / "Podman" / "+TARGETS").exists()
    assert (src / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Podman" / "Podman.xml").exists()
    assert (src / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Podman" / "Podman.php").exists()
    assert (src / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Podman" / "forms" / "general.xml").exists()
    assert (src / "opnsense" / "mvc" / "app" / "views" / "OPNsense" / "Podman" / "general.volt").exists()
    assert (src / "opnsense" / "mvc" / "app" / "views" / "OPNsense" / "Podman" / "dashboard.volt").exists()
    assert (src / "opnsense" / "scripts" / "OPNsense" / "Podman" / "setup.php").exists()
    assert (src / "opnsense" / "scripts" / "OPNsense" / "Podman" / "manage.py").exists()
