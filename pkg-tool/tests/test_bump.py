"""Tests for the version-write module (ticket #192): bump writes package spec
versions via targeted line edits, preserving formatting."""

import pytest

from pkg_tool import bump

BUILD_SPEC = """\
build_config:
  include:
    go: '1.26'
  src_repo: 'https://github.com/0xERR0R/blocky'
pkg_manifest:
  name: blocky
  origin: opnware/blocky
  version: 0.34.0
  comment: Test fixture package
  www: https://example.com
  maintainer: test@example.com
  prefix: /opt/opnware/pkgs/blocky
"""

REDISTRIBUTE_SPEC = """\
build_config:
  include: {}
redistribute:
  name: btop
  version:
    FreeBSD-14-amd64: "1.4.7"
    FreeBSD-15-amd64: "1.4.7"
  repo: http://pkg.freebsd.org
  path: quarterly/All
"""

ENHANCEMENT_SPEC = """\
build_config:
  include:
    go: '1.25'
  src_repo: 'https://github.com/caddyserver/caddy'
  enhancement_version_separator: '_'
pkg_manifest:
  name: caddy
  origin: opnware/caddy
  version: 2.11.4_2
  comment: Test fixture package
  www: https://example.com
  maintainer: test@example.com
  prefix: /opt/opnware/pkgs/caddy
"""


@pytest.fixture
def repo(tmp_path, monkeypatch):
    pkgs = tmp_path / "pkgs"
    (pkgs / "blocky").mkdir(parents=True)
    (pkgs / "btop").mkdir()
    (pkgs / "caddy").mkdir()
    (pkgs / "blocky" / "config.yml").write_text(BUILD_SPEC)
    (pkgs / "btop" / "config.yml").write_text(REDISTRIBUTE_SPEC)
    (pkgs / "caddy" / "config.yml").write_text(ENHANCEMENT_SPEC)
    monkeypatch.chdir(tmp_path)
    return tmp_path


def test_bump_build_version_changes_only_the_version_line(repo):
    bump("blocky", version="0.35.0")

    assert (repo / "pkgs" / "blocky" / "config.yml").read_text() == BUILD_SPEC.replace(
        "  version: 0.34.0", "  version: 0.35.0"
    )


def test_bump_redistribute_writes_one_abi_arch_keeping_quotes(repo):
    bump("btop", version="1.5.0", abi_arch="FreeBSD-15-amd64")

    content = (repo / "pkgs" / "btop" / "config.yml").read_text()
    assert content == REDISTRIBUTE_SPEC.replace(
        '    FreeBSD-15-amd64: "1.4.7"', '    FreeBSD-15-amd64: "1.5.0"'
    )
    assert 'FreeBSD-14-amd64: "1.4.7"' in content  # untouched


def test_bump_enhancement_increments_after_separator(repo):
    bump("caddy", bump_enhancement=True)

    assert (repo / "pkgs" / "caddy" / "config.yml").read_text() == ENHANCEMENT_SPEC.replace(
        "  version: 2.11.4_2", "  version: 2.11.4_3"
    )


def test_bump_enhancement_requires_separator(repo):
    with pytest.raises(ValueError, match="enhancement_version_separator"):
        bump("blocky", bump_enhancement=True)


def test_bump_redistribute_requires_abi_arch(repo):
    with pytest.raises(ValueError, match="abi-arch"):
        bump("btop", version="1.5.0")


def test_bump_unknown_abi_arch_fails(repo):
    with pytest.raises(ValueError, match="FreeBSD-16-amd64"):
        bump("btop", version="1.5.0", abi_arch="FreeBSD-16-amd64")


def test_bump_missing_package_fails(repo):
    with pytest.raises(FileNotFoundError):
        bump("nonexistent", version="1.0.0")


def test_bump_requires_version_or_enhancement(repo):
    with pytest.raises(ValueError, match="--version"):
        bump("blocky")


def test_bump_fails_loudly_when_version_line_missing(repo):
    (repo / "pkgs" / "blocky" / "config.yml").write_text(
        BUILD_SPEC.replace("  version: 0.34.0", "  comment: no version here")
    )

    with pytest.raises(ValueError, match="version"):
        bump("blocky", version="0.35.0")


def test_bump_redistribute_ignores_leaf_outside_section(repo):
    weird = REDISTRIBUTE_SPEC.replace(
        "build_config:\n  include: {}",
        'build_config:\n  include: {}\n  FreeBSD-15-amd64: "9.9.9"',
    )
    (repo / "pkgs" / "btop" / "config.yml").write_text(weird)

    bump("btop", version="1.5.0", abi_arch="FreeBSD-15-amd64")

    content = (repo / "pkgs" / "btop" / "config.yml").read_text()
    assert '  FreeBSD-15-amd64: "9.9.9"' in content  # outside the redistribute section untouched
    assert '    FreeBSD-15-amd64: "1.5.0"' in content
