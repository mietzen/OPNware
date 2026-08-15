"""Tests for the version-discovery module (ticket #192): check_updates walks
package specs, compares against remote sources via adapters, and emits the
update matrix. Network is stubbed via monkeypatched requests."""

import io
import json
import tarfile

import requests
import zstandard as zstd

from pkg_tool import check_updates

GH_SPEC = """\
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
"""

GH_SPEC_CURRENT = GH_SPEC.replace("version: 0.34.0", "version: 0.35.0")

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


class FakeResponse:
    def __init__(self, status_code=200, text="", content=b"", json_data=None):
        self.status_code = status_code
        self.text = text
        self.content = content
        self._json = json_data

    def json(self):
        return self._json


def tzst_bytes(entries):
    """A zstd tar containing packagesite.yaml with one JSON line per entry."""
    raw = "".join(json.dumps(e) + "\n" for e in entries).encode()
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode="w", format=tarfile.PAX_FORMAT) as tar:
        info = tarfile.TarInfo("packagesite.yaml")
        info.size = len(raw)
        tar.addfile(info, io.BytesIO(raw))
    return zstd.ZstdCompressor().compress(data.getvalue())


def make_repo(tmp_path, specs):
    for name, spec in specs.items():
        d = tmp_path / "pkgs" / name
        d.mkdir(parents=True)
        (d / "config.yml").write_text(spec)
    return tmp_path


def test_gh_adapter_detects_newer_version(tmp_path, monkeypatch):
    make_repo(tmp_path, {"blocky": GH_SPEC})

    def fake_get(url, **kwargs):
        assert "api.github.com" in url
        return FakeResponse(json_data={"tag_name": "v0.36.0"})

    monkeypatch.setattr(requests, "get", fake_get)
    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix["pkg"] == ["blocky"]
    assert matrix["include"] == [{"pkg": "blocky", "abi_arch": "ALL", "version": "0.36.0"}]


def test_gh_adapter_no_update_emits_nothing(tmp_path, monkeypatch):
    make_repo(tmp_path, {"blocky": GH_SPEC_CURRENT})
    monkeypatch.setattr(requests, "get", lambda url, **kwargs: FakeResponse(json_data={"tag_name": "v0.35.0"}))

    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix == {"pkg": [], "include": []}

def test_bsd_packagesite_adapter_detects_newer_version(tmp_path, monkeypatch):
    make_repo(tmp_path, {"btop": REDISTRIBUTE_SPEC})

    def fake_get(url, **kwargs):
        if url.endswith("meta.conf"):
            return FakeResponse(text="packing_format = tzst")
        if url.endswith("packagesite.pkg"):
            return FakeResponse(content=tzst_bytes([{"name": "btop", "version": "1.5.0"}]))
        raise AssertionError(f"unexpected url: {url}")

    monkeypatch.setattr(requests, "get", fake_get)
    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix["pkg"] == ["btop", "btop"]
    assert matrix["include"] == [
        {"pkg": "btop", "abi_arch": "FreeBSD-14-amd64", "version": "1.5.0"},
        {"pkg": "btop", "abi_arch": "FreeBSD-15-amd64", "version": "1.5.0"},
    ]


def test_plugin_specs_are_skipped_not_errors(tmp_path):
    plugin_spec = """\
build_config:
  include: {}
plugin:
  opnsense_version: "26.7"
  conflicts:
    - os-caddy
pkg_manifest:
  name: caddy
  origin: opnware/os-caddy
  version: 2.2.0
  comment: plugin
  www: https://example.com
  maintainer: test@example.com
  prefix: /usr/local
"""
    make_repo(tmp_path, {"caddy": plugin_spec})

    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix == {"pkg": [], "include": []}


def test_static_asset_specs_are_skipped_not_errors(tmp_path):
    static_spec = """\
build_config:
  include: {}
pkg_manifest:
  name: editor
  origin: opnware/editor
  version: 0.1.0
  comment: static assets
  www: https://example.com
  maintainer: test@example.com
  prefix: /usr/local
"""
    make_repo(tmp_path, {"editor": static_spec})

    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix == {"pkg": [], "include": []}


def test_sourceforge_adapter_detects_newer_version(tmp_path, monkeypatch):
    sf_spec = GH_SPEC.replace(
        "src_repo: 'https://github.com/0xERR0R/blocky'",
        "src_repo: 'https://git.code.sf.net/p/zsh/code'",
    )
    make_repo(tmp_path, {"zsh": sf_spec})

    def fake_get(url, **kwargs):
        assert "sourceforge.net" in url
        return FakeResponse(json_data={"release": {"filename": "/projects/zsh/files/5.9.1/zsh-5.9.1.tar.gz"}})

    monkeypatch.setattr(requests, "get", fake_get)
    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix["include"] == [{"pkg": "zsh", "abi_arch": "ALL", "version": "5.9.1"}]
