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


CONTENT_SPEC = """\
build_config:
  include:
    node: '22'
content:
  repo: https://github.com/bastienwirtz/homer
  version: 26.4.2
plugin:
  opnsense_version: "26.7"
pkg_manifest:
  name: homer
  origin: opnware/os-homer
  version: 0.1.0
  comment: content plugin
  www: https://example.com
  maintainer: test@example.com
  prefix: /usr/local
"""


VENDOR_SPEC = """\
build_config:
  include: {}
vendor:
  npm: monaco-editor
pkg_manifest:
  name: monaco-editor
  origin: opnware/monaco-editor
  version: 0.56.0_1
  comment: vendored asset
  www: https://example.com
  maintainer: test@example.com
  prefix: /usr/local
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


def test_gh_adapter_strips_revision_suffix_before_compare(tmp_path, monkeypatch):
    # A FreeBSD revision suffix (_N) marks package-only changes and is not a
    # version difference — a GitHub release equal to the base version must not
    # emit an update (latent twin of the vendor-branch fix, ticket #242).
    make_repo(tmp_path, {"blocky": GH_SPEC.replace("version: 0.34.0", "version: 0.34.0_1")})
    monkeypatch.setattr(requests, "get", lambda url, **kwargs: FakeResponse(json_data={"tag_name": "v0.34.0"}))

    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix == {"pkg": [], "include": []}


def test_gh_adapter_revision_suffix_still_emits_for_newer_remote(tmp_path, monkeypatch):
    # Same revision-suffixed local version, but the remote genuinely moved:
    # the update must still be emitted.
    make_repo(tmp_path, {"blocky": GH_SPEC.replace("version: 0.34.0", "version: 0.34.0_1")})
    monkeypatch.setattr(requests, "get", lambda url, **kwargs: FakeResponse(json_data={"tag_name": "v0.36.0"}))

    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix["include"] == [{"pkg": "blocky", "abi_arch": "ALL", "version": "0.36.0"}]

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


def test_content_adapter_tracks_plugin_bundled_content(tmp_path, monkeypatch):
    # A plugin with a content section is NOT skipped: its bundled content
    # (e.g. the Homer dashboard) follows the upstream repo releases.
    make_repo(tmp_path, {"homer": CONTENT_SPEC})

    monkeypatch.setattr(requests, "get", lambda url, **kw: FakeResponse(json_data={"tag_name": "v26.5.0"}))
    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix["include"] == [{"pkg": "homer", "abi_arch": "content", "version": "26.5.0"}]


def test_content_adapter_no_update_emits_nothing(tmp_path, monkeypatch):
    make_repo(tmp_path, {"homer": CONTENT_SPEC})
    monkeypatch.setattr(requests, "get", lambda url, **kw: FakeResponse(json_data={"tag_name": "v26.4.2"}))

    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix == {"pkg": [], "include": []}


def test_vendor_adapter_emits_update_entry(tmp_path, monkeypatch):
    # A vendored npm asset (the shared editor) is checked against the npm
    # registry; a newer release emits a 'vendor' entry the workflow turns
    # into a refresh PR (no auto-merge).
    make_repo(tmp_path, {"monaco-editor": VENDOR_SPEC})

    monkeypatch.setattr(requests, "get", lambda url, **kw: FakeResponse(json_data={"version": "0.57.0"}))
    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix == {
        "pkg": ["monaco-editor"],
        "include": [{"pkg": "monaco-editor", "abi_arch": "vendor", "version": "0.57.0"}],
    }


def test_vendor_adapter_no_update_emits_nothing(tmp_path, monkeypatch):
    make_repo(tmp_path, {"monaco-editor": VENDOR_SPEC})
    monkeypatch.setattr(requests, "get", lambda url, **kw: FakeResponse(json_data={"version": "0.56.0"}))

    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix == {"pkg": [], "include": []}


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
  name: monaco-editor
  origin: opnware/monaco-editor
  version: 0.1.0
  comment: static assets
  www: https://example.com
  maintainer: test@example.com
  prefix: /usr/local
"""
    make_repo(tmp_path, {"monaco-editor": static_spec})

    matrix = check_updates(str(tmp_path / 'pkgs'))

    assert matrix == {"pkg": [], "include": []}
