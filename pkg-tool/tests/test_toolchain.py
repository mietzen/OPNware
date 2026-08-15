"""Repo-seam tests (ticket #206): the os-caddy module-rebuild toolchain —
go126, go, xcaddy — lives in pkgs/ as validated redistribute specs whose
pinned versions match the live FreeBSD quarterly packagesite.

The pinned versions are the independent source of truth: verified against
pkg.freebsd.org quarterly on 2026-08-15 (go126-1.26.5, go-1.25_20,2,
xcaddy-0.4.5_14; the go/xcaddy chain currently tracks go125).
"""

import pytest

from pkg_tool import _load_spec, build_matrix

TOOLCHAIN = {
    "go125": ("go125", "1.25.12"),
    "go126": ("go126", "1.26.5"),
    "go": ("go", "1.25_20,2"),
    "xcaddy": ("xcaddy", "0.4.5_14"),
}

REPO_CONFIG = """\
pkg-repo:
  abi:
    - 15
  arch:
    - amd64
meta-conf:
  version: 2
  packing_format: tzst
  manifests: packagesite.yaml
"""


@pytest.fixture
def repo(tmp_path):
    """A fixture repo mirroring the real pkgs/ toolchain specs."""
    for name, (pkg, version) in TOOLCHAIN.items():
        d = tmp_path / "pkgs" / name
        d.mkdir(parents=True)
        (d / "build.sh").touch()
        (d / "config.yml").write_text(
            "build_config:\n  include: {}\n"
            "redistribute:\n"
            f"  name: {pkg}\n"
            "  version:\n"
            f'    FreeBSD-15-amd64: "{version}"\n'
            "  repo: http://pkg.freebsd.org\n"
            "  path: quarterly/All\n")
    (tmp_path / "config.yml").write_text(REPO_CONFIG)
    return tmp_path


def test_toolchain_specs_validate_and_pin_quarterly_versions(repo):
    for name, (pkg, version) in TOOLCHAIN.items():
        spec = _load_spec(str(repo / "pkgs" / name / "config.yml"))
        assert spec["redistribute"]["name"] == pkg
        assert spec["redistribute"]["version"]["FreeBSD-15-amd64"] == version
        assert spec["redistribute"]["repo"] == "http://pkg.freebsd.org"
        assert spec["redistribute"]["path"] == "quarterly/All"


def test_toolchain_specs_are_discovered_by_build_matrix(repo):
    matrix = build_matrix(packages=None, pkgs_dir=str(repo / "pkgs"), repo_config=str(repo / "config.yml"))
    assert sorted(matrix["pkg_name"]) == ["go", "go125", "go126", "xcaddy"]
    assert matrix["include"] == [
        {"pkg_name": "go"},
        {"pkg_name": "go125"},
        {"pkg_name": "go126"},
        {"pkg_name": "xcaddy"},
    ]
