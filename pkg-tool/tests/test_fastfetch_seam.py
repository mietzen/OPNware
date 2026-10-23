"""Tests for fastfetch package redistribution and dependencies."""

from pathlib import Path
from pkg_tool import _load_spec

ROOT_DIR = Path(__file__).resolve().parents[2]
PKGS_DIR = ROOT_DIR / "pkgs"

FASTFETCH_PKGS = [
    ("fastfetch", "2.69.0"),
    ("hwdata", "0.411,1"),
    ("yyjson", "0.13.0"),
]


def test_fastfetch_redistribute_specs_valid():
    for name, expected_version in FASTFETCH_PKGS:
        config_path = PKGS_DIR / name / "config.yml"
        assert config_path.exists(), f"{name}/config.yml missing"

        spec = _load_spec(str(config_path))
        redist = spec.get("redistribute")
        assert redist, f"{name}/config.yml missing redistribute section"
        assert redist["name"] == name
        assert redist["version"]["FreeBSD-15-amd64"] == expected_version
        assert redist["repo"] == "http://pkg.freebsd.org"
        assert redist["path"] == "quarterly/All"

        build_sh = PKGS_DIR / name / "build.sh"
        assert build_sh.exists(), f"{name}/build.sh missing"
        assert build_sh.stat().st_mode & 0o111, f"{name}/build.sh not executable"
