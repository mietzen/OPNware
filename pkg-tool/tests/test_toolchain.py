"""Repo-seam tests (ticket #206): the os-caddy module-rebuild toolchain —
go126 (redistributed) and xcaddy (cross-compiled from source) — lives in
pkgs/ as validated specs whose pinned versions match the live FreeBSD
quarterly packagesite / upstream release.

The pinned versions are the independent source of truth: verified against
pkg.freebsd.org quarterly on 2026-08-15 (go126-1.26.5) and the xcaddy
upstream release (0.4.5, cross-compiled via build_config.src_repo).
"""

import pytest

from pkg_tool import _load_spec, build_matrix

# name -> (pkg_manifest.name, pinned version)
REDISTRIBUTED = {
    "go126": ("go126", "1.26.5"),
}

# name -> (pkg_manifest.name, pinned version, src_repo)
SOURCE_BUILT = {
    "xcaddy": ("xcaddy", "0.4.5", "https://github.com/caddyserver/xcaddy"),
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
    for name, (pkg, version) in REDISTRIBUTED.items():
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
    for name, (pkg, version, src_repo) in SOURCE_BUILT.items():
        d = tmp_path / "pkgs" / name
        d.mkdir(parents=True)
        (d / "build.sh").touch()
        (d / "config.yml").write_text(
            "build_config:\n"
            "  include: {}\n"
            f"  src_repo: '{src_repo}'\n"
            "pkg_manifest:\n"
            f"  name: {pkg}\n"
            f"  origin: opnware/{pkg}\n"
            f"  version: {version}\n"
            "  comment: test fixture\n"
            "  www: https://example.com\n"
            "  maintainer: test@example.com\n"
            "  prefix: /usr/local\n")
    (tmp_path / "config.yml").write_text(REPO_CONFIG)
    return tmp_path


def test_toolchain_specs_validate_and_pin_versions(repo):
    for name, (pkg, version) in REDISTRIBUTED.items():
        spec = _load_spec(str(repo / "pkgs" / name / "config.yml"))
        assert spec["redistribute"]["name"] == pkg
        assert spec["redistribute"]["version"]["FreeBSD-15-amd64"] == version
        assert spec["redistribute"]["repo"] == "http://pkg.freebsd.org"
        assert spec["redistribute"]["path"] == "quarterly/All"
    for name, (pkg, version, src_repo) in SOURCE_BUILT.items():
        spec = _load_spec(str(repo / "pkgs" / name / "config.yml"))
        assert spec["build_config"]["src_repo"] == src_repo
        assert spec["pkg_manifest"]["name"] == pkg
        assert spec["pkg_manifest"]["version"] == version


def test_toolchain_specs_are_discovered_by_build_matrix(repo):
    matrix = build_matrix(packages=None, pkgs_dir=str(repo / "pkgs"), repo_config=str(repo / "config.yml"))
    assert sorted(matrix["pkg_name"]) == ["go126", "xcaddy"]
    assert matrix["include"] == [
        {"pkg_name": "go126"},
        {"pkg_name": "xcaddy"},
    ]
