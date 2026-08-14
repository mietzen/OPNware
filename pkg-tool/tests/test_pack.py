"""Tests for the packing module — the pre-agreed seam (ticket #190 D5):

payload dir + package spec in, valid .pkg + packagesite_info.json out.
Golden values were captured from the pre-refactor tooling (current packing tail)
on a deterministic fixture, so they are an independent source of truth.
"""

import hashlib
import io
import json
import os
import shutil
import tarfile

import pytest
import yaml
import zstandard as zstd

from pkg_tool import pack

FIXTURE_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_SRC = os.path.normpath(
    os.path.join(FIXTURE_DIR, "..", "..", "service_templates", "default.jinja")
)

BLOCKY_BINARY = bytes(range(256)) * 4  # 1024 deterministic bytes
LICENSE = "Apache License 2.0 fixture text\n"
SOURCE = "https://github.com/0xERR0R/blocky/archive/refs/tags/v0.34.0.tar.gz\n"
APP_CONFIG = "config: {}\n"

SPEC_WITH_SERVICE = """\
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
  users:
    - blocky
  groups:
    - blocky
  licenselogic: single
  licenses:
    - APACHE20
  desc: |
    Deterministic fixture description.
  scripts:
    pre-install: |
      echo fixture
pkg_service:
  template: default
  vars:
    COMMAND: /opt/opnware/pkgs/blocky/blocky --config config.yml
"""

_SPEC_DICT = yaml.safe_load(SPEC_WITH_SERVICE)
SPEC_NO_SERVICE = yaml.safe_dump({k: v for k, v in _SPEC_DICT.items() if k != "pkg_service"})

# Captured 2026-08-14 from the pre-refactor packing tail on the identical fixture.
GOLDEN_MANIFEST = {
    "name": "blocky",
    "origin": "opnware/blocky",
    "version": "0.34.0",
    "comment": "Test fixture package",
    "www": "https://example.com",
    "maintainer": "test@example.com",
    "prefix": "/opt/opnware/pkgs/blocky",
    "users": ["blocky"],
    "groups": ["blocky"],
    "licenselogic": "single",
    "licenses": ["APACHE20"],
    "desc": "Deterministic fixture description.\n",
    "scripts": {"pre-install": "echo fixture\n"},
    "abi": "FreeBSD:15:amd64",
    "arch": "freebsd:15:x86:64",
    "flatsize": 2212,
    "files": {
        "/etc/rc.d/blocky": "fb11965ee116bae53007265de0e3fea2d946d8c37fdc806b23b825086ab6c0c7",
        "/opt/opnware/pkgs/blocky/LICENSE": "7073bc5face2ef6d92e47bb715d9a9427eba1bbef26ac59babdbea901e00fe54",
        "/opt/opnware/pkgs/blocky/SOURCE": "9d1c2135092d4bcdccd6bab6ee476d566551a85d39d93a01ec8451db6924debb",
        "/opt/opnware/pkgs/blocky/blocky": "785b0751fc2c53dc14a4ce3d800e69ef9ce1009eb327ccf458afe09c242c26c9",
        "/opt/opnware/pkgs/blocky/config.yml": "009c4672fda30d3313d1e114efe92407bd27fdbf08ca7f85b781afacad87e96a",
        "/opt/opnware/services/blocky/blocky": "fb11965ee116bae53007265de0e3fea2d946d8c37fdc806b23b825086ab6c0c7",
    },
}

EXPECTED_MEMBERS = [
    "+COMPACT_MANIFEST",
    "+MANIFEST",
    "/opt/opnware/pkgs/blocky/LICENSE",
    "/opt/opnware/pkgs/blocky/SOURCE",
    "/opt/opnware/pkgs/blocky/blocky",
    "/opt/opnware/pkgs/blocky/config.yml",
    "/opt/opnware/services/blocky/blocky",
    "/etc/rc.d/blocky",
]


def make_fixture(tmp_path, spec):
    """Build a blocky-like staged payload + spec; returns (config_path, payload_dir, output_dir)."""
    (tmp_path / "service_templates").mkdir()
    shutil.copy(TEMPLATE_SRC, tmp_path / "service_templates" / "default.jinja")
    # config lives two levels under the root, mirroring pkgs/<name>/config.yml
    cfg_dir = tmp_path / "pkgs" / "blocky"
    cfg_dir.mkdir(parents=True)
    (cfg_dir / "config.yml").write_text(spec)

    payload = tmp_path / "dist" / "pkg"
    pkg_dir = payload / "opt/opnware/pkgs/blocky"
    pkg_dir.mkdir(parents=True)
    (pkg_dir / "blocky").write_bytes(BLOCKY_BINARY)
    (pkg_dir / "LICENSE").write_text(LICENSE)
    (pkg_dir / "SOURCE").write_text(SOURCE)
    (pkg_dir / "config.yml").write_text(APP_CONFIG)
    os.chmod(pkg_dir / "blocky", 0o755)

    return str(cfg_dir / "config.yml"), str(payload), str(tmp_path / "dist")


def unpack(pkg_path):
    """Return (member-name->TarInfo dict, {manifest-name: parsed JSON})."""
    with open(pkg_path, "rb") as f:
        dctx = zstd.ZstdDecompressor()
        with dctx.stream_reader(f) as s:
            buf = io.BytesIO(s.read())
    with tarfile.open(fileobj=buf, mode="r:") as tar:
        members = {m.name: m for m in tar.getmembers()}
        manifests = {
            name: json.loads(tar.extractfile(name).read().decode())
            for name in ("+MANIFEST", "+COMPACT_MANIFEST")
        }
    return members, manifests


def test_pack_creates_valid_package_with_service(tmp_path):
    config, payload, dist = make_fixture(tmp_path, SPEC_WITH_SERVICE)

    pack(config, abi="15", arch="amd64", payload_dir=payload, output_dir=dist)

    pkg_path = os.path.join(dist, "blocky-0.34.0.pkg")
    assert os.path.exists(pkg_path)

    with open(os.path.join(dist, "packagesite_info.json")) as f:
        info = json.load(f)
    assert info["path"] == "All/blocky-0.34.0.pkg"
    assert info["repopath"] == "All/blocky-0.34.0.pkg"
    with open(pkg_path, "rb") as f:
        assert info["sum"] == hashlib.sha256(f.read()).hexdigest()
    assert info["pkgsize"] == os.path.getsize(pkg_path)

    members, manifests = unpack(pkg_path)
    assert list(members) == EXPECTED_MEMBERS

    link = members["/etc/rc.d/blocky"]
    assert link.issym()
    assert link.linkname == "../../opt/opnware/services/blocky/blocky"

    manifest = manifests["+MANIFEST"]
    assert manifest["abi"] == "FreeBSD:15:amd64"
    assert manifest["arch"] == "freebsd:15:x86:64"
    assert manifest["version"] == "0.34.0"
    assert set(manifest["files"]) == set(GOLDEN_MANIFEST["files"])

    compact = manifests["+COMPACT_MANIFEST"]
    assert "files" not in compact
    assert "scripts" not in compact
    assert compact["version"] == "0.34.0"

    # pack cleans up its own staging
    assert sorted(os.listdir(dist)) == ["blocky-0.34.0.pkg", "packagesite_info.json"]


def test_pack_golden_manifest(tmp_path):
    config, payload, dist = make_fixture(tmp_path, SPEC_WITH_SERVICE)

    pack(config, abi="15", arch="amd64", payload_dir=payload, output_dir=dist)

    _, manifests = unpack(os.path.join(dist, "blocky-0.34.0.pkg"))
    assert manifests["+MANIFEST"] == GOLDEN_MANIFEST


def test_pack_without_service_has_no_service_members(tmp_path):
    config, payload, dist = make_fixture(tmp_path, SPEC_NO_SERVICE)

    pack(config, abi="15", arch="amd64", payload_dir=payload, output_dir=dist)

    members, _ = unpack(os.path.join(dist, "blocky-0.34.0.pkg"))
    names = list(members)
    assert "/etc/rc.d/blocky" not in names
    assert "/opt/opnware/services/blocky/blocky" not in names
    assert "/opt/opnware/pkgs/blocky/blocky" in names
    assert sorted(os.listdir(dist)) == ["blocky-0.34.0.pkg", "packagesite_info.json"]


def test_pack_replaces_stale_rc_d_link(tmp_path):
    config, payload, dist = make_fixture(tmp_path, SPEC_WITH_SERVICE)
    rc_dir = os.path.join(payload, "etc", "rc.d")
    os.makedirs(rc_dir)
    stale = os.path.join(rc_dir, "blocky")
    os.symlink("../../opt/opnware/services/blocky/OLD", stale)

    pack(config, abi="15", arch="amd64", payload_dir=payload, output_dir=dist)

    members, _ = unpack(os.path.join(dist, "blocky-0.34.0.pkg"))
    assert members["/etc/rc.d/blocky"].linkname == "../../opt/opnware/services/blocky/blocky"


def test_pack_fails_loudly_when_payload_missing(tmp_path):
    config, payload, dist = make_fixture(tmp_path, SPEC_NO_SERVICE)
    shutil.rmtree(payload)

    with pytest.raises(FileNotFoundError):
        pack(config, abi="15", arch="amd64", payload_dir=payload, output_dir=dist)
