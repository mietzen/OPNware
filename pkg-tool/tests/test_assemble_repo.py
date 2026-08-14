"""Tests for the repo assembly module — the pre-agreed seam (ticket #191):

flat artifacts dir + repo config in, complete serveable pages tree out.
"""

import io
import json
import os
import shutil
import tarfile

import pytest
import zstandard as zstd

from pkg_tool import assemble_repo, pack
from test_pack import SPEC_WITH_SERVICE, make_fixture

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


def make_artifact(artifacts, name, abi_arch="FreeBSD:15:amd64", extra=None):
    """A fake build output: one .pkg + its packagesite_info.json."""
    d = os.path.join(artifacts, name)
    os.makedirs(d)
    pkg = os.path.join(d, f"{name}.pkg")
    with open(pkg, "wb") as f:
        f.write(b"fake-pkg-bytes")
    info = {"name": name, "version": "1.0.0", "abi": abi_arch}
    if extra:
        info.update(extra)
    with open(os.path.join(d, "packagesite_info.json"), "w") as f:
        json.dump(info, f)
    return pkg


def read_tzst(path):
    """Return {member-name: bytes} from a zstd-compressed tar."""
    with open(path, "rb") as f:
        data = io.BytesIO(zstd.ZstdDecompressor().stream_reader(f).read())
    with tarfile.open(fileobj=data, mode="r:") as tar:
        return {m.name: tar.extractfile(m.name).read() for m in tar.getmembers()}


def test_assemble_repo_builds_full_tree(tmp_path):
    artifacts = tmp_path / "artifacts"
    artifacts.mkdir()
    make_artifact(str(artifacts), "alpha")
    make_artifact(str(artifacts), "beta", extra={"path": "All/beta-1.0.0.pkg"})
    config = tmp_path / "config.yml"
    config.write_text(REPO_CONFIG)
    pages = tmp_path / "pages"

    assemble_repo(str(artifacts), str(config), owner="mietzen", repo="OPNware", output_dir=str(pages))

    latest = pages / "FreeBSD:15:amd64" / "latest"
    assert (latest / "All" / "alpha.pkg").read_bytes() == b"fake-pkg-bytes"
    assert (latest / "All" / "beta.pkg").exists()

    # packagesite.yaml accumulated (two lines) then tzst'd and removed
    assert not (latest / "packagesite.yaml").exists()
    members = read_tzst(str(latest / "packagesite.tzst"))
    assert list(members) == ["packagesite.yaml"]
    lines = [json.loads(l) for l in members["packagesite.yaml"].decode().strip().split("\n")]
    assert [l["name"] for l in lines] == ["alpha", "beta"]

    link = latest / "packagesite.pkg"
    assert link.is_symlink()
    assert os.readlink(link) == "./packagesite.tzst"

    assert (latest / "meta.conf").read_text() == (
        '{\n'
        '  "version": 2,\n'
        '  "packing_format": "tzst",\n'
        '  "manifests": "packagesite.yaml"\n'
        '}\n'
    )

    conf = (pages / "opnware.conf").read_text()
    assert 'url: "https://mietzen.github.io/OPNware/${ABI}/latest"' in conf

    assert (pages / "robots.txt").read_text() == "User-agent: *\nDisallow: /\n"
    for idx in [pages / "index.html", latest / "index.html", latest / "All" / "index.html"]:
        assert idx.exists()


def test_assemble_repo_rejects_undeclared_abi(tmp_path):
    artifacts = tmp_path / "artifacts"
    artifacts.mkdir()
    make_artifact(str(artifacts), "rogue", abi_arch="FreeBSD:16:amd64")
    config = tmp_path / "config.yml"
    config.write_text(REPO_CONFIG)

    with pytest.raises(ValueError, match="rogue"):
        assemble_repo(str(artifacts), str(config), owner="o", repo="r", output_dir=str(tmp_path / "pages"))


def test_assemble_repo_reads_abi_from_pkg_when_no_sibling_json(tmp_path):
    config, payload, dist = make_fixture(tmp_path, SPEC_WITH_SERVICE)
    pack(config, abi="15", arch="amd64", payload_dir=payload, output_dir=dist)

    artifacts = tmp_path / "artifacts"
    artifacts.mkdir()
    shutil.copy(os.path.join(dist, "blocky-0.34.0.pkg"), artifacts / "blocky-0.34.0.pkg")
    repo_cfg = tmp_path / "config.yml"
    repo_cfg.write_text(REPO_CONFIG)
    pages = tmp_path / "pages"

    assemble_repo(str(artifacts), str(repo_cfg), owner="o", repo="r", output_dir=str(pages))

    assert (pages / "FreeBSD:15:amd64" / "latest" / "All" / "blocky-0.34.0.pkg").exists()
    content = read_tzst(str(pages / "FreeBSD:15:amd64" / "latest" / "packagesite.tzst"))
    line = json.loads(content["packagesite.yaml"].decode().strip())
    assert line["name"] == "blocky"
    assert line["path"] == "All/blocky-0.34.0.pkg"


def test_assemble_repo_is_idempotent_on_rerun(tmp_path):
    artifacts = tmp_path / "artifacts"
    artifacts.mkdir()
    make_artifact(str(artifacts), "alpha")
    config = tmp_path / "config.yml"
    config.write_text(REPO_CONFIG)
    pages = tmp_path / "pages"

    assemble_repo(str(artifacts), str(config), owner="o", repo="r", output_dir=str(pages))
    assemble_repo(str(artifacts), str(config), owner="o", repo="r", output_dir=str(pages))

    members = read_tzst(str(pages / "FreeBSD:15:amd64" / "latest" / "packagesite.tzst"))
    lines = members["packagesite.yaml"].decode().strip().split("\n")
    assert len(lines) == 1  # no duplicated accumulation across runs


def test_assemble_repo_fails_when_sibling_json_has_no_abi(tmp_path):
    artifacts = tmp_path / "artifacts"
    artifacts.mkdir()
    d = artifacts / "broken"
    d.mkdir()
    with open(d / "broken.pkg", "wb") as f:
        f.write(b"x")
    with open(d / "packagesite_info.json", "w") as f:
        json.dump({"name": "broken"}, f)
    config = tmp_path / "config.yml"
    config.write_text(REPO_CONFIG)

    with pytest.raises(ValueError, match="broken.pkg"):
        assemble_repo(str(artifacts), str(config), owner="o", repo="r", output_dir=str(tmp_path / "pages"))


def test_assemble_repo_fails_when_no_packages(tmp_path):
    artifacts = tmp_path / "artifacts"
    artifacts.mkdir()
    config = tmp_path / "config.yml"
    config.write_text(REPO_CONFIG)

    with pytest.raises(ValueError, match="No .pkg"):
        assemble_repo(str(artifacts), str(config), owner="o", repo="r", output_dir=str(tmp_path / "pages"))
