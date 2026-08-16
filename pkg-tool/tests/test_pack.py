"""Tests for the packing module — the pre-agreed seam (ticket #190 D5):

payload dir + package spec in, valid .pkg + packagesite_info.json out.
Golden values were captured from the pre-refactor tooling (current packing tail)
on a deterministic fixture, so they are an independent source of truth.

Layout convention (ticket #205): payloads stage on FreeBSD default paths —
binaries in usr/local/bin, docs in usr/local/share/doc/<name>/, configs in
usr/local/etc/<name>/ — and the manifest prefix is /usr/local.
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

BLOCKY_BINARY = bytes(range(256)) * 4  # 1024 deterministic bytes
LICENSE = "Apache License 2.0 fixture text\n"
SOURCE = "https://github.com/0xERR0R/blocky/archive/refs/tags/v0.34.0.tar.gz\n"
APP_CONFIG = "config: {}\n"

SPEC = """\
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
  prefix: /usr/local
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
"""

# Captured 2026-08-14 from the pre-refactor packing tail; file hashes are
# content-derived (unchanged across the layout move), paths and member set
# follow the FreeBSD-default layout.
GOLDEN_MANIFEST = {
    "name": "blocky",
    "origin": "opnware/blocky",
    "version": "0.34.0",
    "comment": "Test fixture package",
    "www": "https://example.com",
    "maintainer": "test@example.com",
    "prefix": "/usr/local",
    "users": ["blocky"],
    "groups": ["blocky"],
    "licenselogic": "single",
    "licenses": ["APACHE20"],
    "desc": "Deterministic fixture description.\n",
    "scripts": {"pre-install": "echo fixture\n"},
    "abi": "FreeBSD:15:amd64",
    "arch": "freebsd:15:x86:64",
    "flatsize": 1166,
    "files": {
        "/usr/local/bin/blocky": "785b0751fc2c53dc14a4ce3d800e69ef9ce1009eb327ccf458afe09c242c26c9",
        "/usr/local/etc/blocky/config.yml": "009c4672fda30d3313d1e114efe92407bd27fdbf08ca7f85b781afacad87e96a",
        "/usr/local/share/doc/blocky/LICENSE": "7073bc5face2ef6d92e47bb715d9a9427eba1bbef26ac59babdbea901e00fe54",
        "/usr/local/share/doc/blocky/SOURCE": "9d1c2135092d4bcdccd6bab6ee476d566551a85d39d93a01ec8451db6924debb",
        "/usr/local/share/licenses/blocky-0.34.0/APACHE20": "7073bc5face2ef6d92e47bb715d9a9427eba1bbef26ac59babdbea901e00fe54",
    },
}

EXPECTED_MEMBERS = [
    "+COMPACT_MANIFEST",
    "+MANIFEST",
    "/usr/local/bin/blocky",
    "/usr/local/etc/blocky/config.yml",
    "/usr/local/share/doc/blocky/LICENSE",
    "/usr/local/share/doc/blocky/SOURCE",
    "/usr/local/share/licenses/blocky-0.34.0/APACHE20",
]


def make_fixture(tmp_path, spec):
    """Build a blocky-like staged payload + spec; returns (config_path, payload_dir, output_dir)."""
    # config lives two levels under the root, mirroring pkgs/<name>/config.yml
    cfg_dir = tmp_path / "pkgs" / "blocky"
    cfg_dir.mkdir(parents=True)
    (cfg_dir / "config.yml").write_text(spec)

    payload = tmp_path / "dist" / "pkg"
    bin_dir = payload / "usr/local/bin"
    bin_dir.mkdir(parents=True)
    (bin_dir / "blocky").write_bytes(BLOCKY_BINARY)
    os.chmod(bin_dir / "blocky", 0o755)
    doc_dir = payload / "usr/local/share/doc/blocky"
    doc_dir.mkdir(parents=True)
    (doc_dir / "LICENSE").write_text(LICENSE)
    (doc_dir / "SOURCE").write_text(SOURCE)
    etc_dir = payload / "usr/local/etc/blocky"
    etc_dir.mkdir(parents=True)
    (etc_dir / "config.yml").write_text(APP_CONFIG)

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


def test_pack_creates_valid_package(tmp_path):
    config, payload, dist = make_fixture(tmp_path, SPEC)

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
    config, payload, dist = make_fixture(tmp_path, SPEC)

    pack(config, abi="15", arch="amd64", payload_dir=payload, output_dir=dist)

    _, manifests = unpack(os.path.join(dist, "blocky-0.34.0.pkg"))
    assert manifests["+MANIFEST"] == GOLDEN_MANIFEST


PLUGIN_SPEC = """\
build_config:
  include: {}
plugin:
  opnsense_version: "26.7"
  tier: 3
  conflicts:
    - os-caddy
pkg_manifest:
  name: caddy
  origin: opnware/os-caddy
  version: 2.2.0
  comment: Test plugin fixture
  www: https://example.com
  maintainer: test@example.com
  prefix: /usr/local
  licenselogic: single
  licenses:
    - BSD2CLAUSE
  desc: |
    Deterministic plugin fixture.
"""


def make_plugin_fixture(tmp_path, spec=PLUGIN_SPEC):
    """A caddy-like plugin payload: MVC model + configd actions + templates +
    legacy bootstrap (each drives one auto-generated lifecycle hook)."""
    cfg_dir = tmp_path / "pkgs" / "caddy"
    cfg_dir.mkdir(parents=True)
    (cfg_dir / "config.yml").write_text(spec)

    payload = tmp_path / "dist" / "pkg"
    model = payload / "usr/local/opnsense/mvc/app/models/OPNsense/Caddy"
    model.mkdir(parents=True)
    (model / "Caddy.xml").write_text("<model/>")
    actions = payload / "usr/local/opnsense/service/conf/actions.d"
    actions.mkdir(parents=True)
    (actions / "actions_caddy.conf").write_text("[start]\n")
    tpl = payload / "usr/local/opnsense/service/templates/OPNsense/Caddy"
    tpl.mkdir(parents=True)
    (tpl / "+TARGETS").write_text("Caddyfile:/usr/local/etc/caddy/Caddyfile\n")
    inc = payload / "usr/local/etc/inc/plugins.inc.d"
    inc.mkdir(parents=True)
    (inc / "caddy.inc").write_text("<?php\n")

    return str(cfg_dir / "config.yml"), str(payload), str(tmp_path / "dist")


def test_pack_plugin_os_prefix_annotation_hooks_conflicts(tmp_path):
    config, payload, dist = make_plugin_fixture(tmp_path)

    pack(config, abi="15", arch="amd64", payload_dir=payload, output_dir=dist)

    pkg_path = os.path.join(dist, "os-caddy-2.2.0.pkg")
    assert os.path.exists(pkg_path)

    members, manifests = unpack(pkg_path)
    manifest = manifests["+MANIFEST"]
    assert manifest["name"] == "os-caddy"
    assert manifest["origin"] == "opnware/os-caddy"
    # The conflict is carried as the product_conflicts annotation only — the
    # pkg manifest conflicts field must stay absent, otherwise pkg fails the
    # install when the conflict target is not in the local package database.
    assert "conflicts" not in manifest
    assert manifest["annotations"]["product_abi"] == "26.7"
    assert manifest["annotations"]["product_arch"] == "amd64"
    assert manifest["annotations"]["product_id"] == "os-caddy"
    assert manifest["annotations"]["product_name"] == "caddy"
    assert manifest["annotations"]["product_conflicts"] == "os-caddy"

    assert "/usr/local/opnsense/version/caddy" in members

    post = manifest["scripts"]["post-install"]
    assert "configd restart" in post
    assert "run_migrations.php OPNsense/Caddy" in post
    assert "configctl template reload OPNsense/Caddy" in post
    assert "rc.configure_plugins post-install" in post
    assert "register.php install os-caddy" in post
    assert "rc.configure_plugins post-deinstall" in manifest["scripts"]["post-deinstall"]
    assert "register.php remove os-caddy" in manifest["scripts"]["post-deinstall"]

    compact = manifests["+COMPACT_MANIFEST"]
    assert compact["name"] == "os-caddy"
    assert "conflicts" not in compact
    assert "files" not in compact
    assert "scripts" not in compact

    assert sorted(os.listdir(dist)) == ["os-caddy-2.2.0.pkg", "packagesite_info.json"]


def test_pack_fails_loudly_when_payload_missing(tmp_path):
    config, payload, dist = make_fixture(tmp_path, SPEC)
    shutil.rmtree(payload)

    with pytest.raises(FileNotFoundError):
        pack(config, abi="15", arch="amd64", payload_dir=payload, output_dir=dist)
