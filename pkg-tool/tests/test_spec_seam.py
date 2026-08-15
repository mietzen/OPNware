"""Tests for the validated package-spec seam (ticket #193): one validated parse
behind every command entry, errors as key paths, dump/build-matrix as the bash seam."""

import json

import pytest

from pkg_tool import _load_spec, build_matrix, dump

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
  prefix: /usr/local
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


def write(tmp_path, name, content, repo_config=REPO_CONFIG):
    d = tmp_path / "pkgs" / name
    d.mkdir(parents=True)
    (d / "config.yml").write_text(content)
    (tmp_path / "config.yml").write_text(repo_config)
    return tmp_path


class TestValidation:
    def test_valid_build_spec_passes(self, tmp_path):
        write(tmp_path, "blocky", BUILD_SPEC)
        spec = _load_spec(str(tmp_path / "pkgs" / "blocky" / "config.yml"))
        assert spec["pkg_manifest"]["name"] == "blocky"

    def test_valid_redistribute_spec_passes(self, tmp_path):
        write(tmp_path, "btop", REDISTRIBUTE_SPEC)
        spec = _load_spec(str(tmp_path / "pkgs" / "btop" / "config.yml"))
        assert spec["redistribute"]["name"] == "btop"

    def test_neither_manifest_nor_redistribute(self, tmp_path):
        write(tmp_path, "pkg", "build_config:\n  include: {}\n")
        with pytest.raises(ValueError, match="neither pkg_manifest nor redistribute"):
            _load_spec(str(tmp_path / "pkgs" / "pkg" / "config.yml"))

    def test_missing_version_names_the_key(self, tmp_path):
        write(tmp_path, "pkg", "pkg_manifest:\n  name: x\n  origin: o\nbuild_config:\n  include: {}\n")
        with pytest.raises(ValueError, match=r"pkg_manifest\.version"):
            _load_spec(str(tmp_path / "pkgs" / "pkg" / "config.yml"))

    def test_missing_origin_names_the_key(self, tmp_path):
        write(tmp_path, "pkg", "pkg_manifest:\n  name: x\n  version: 1.0\nbuild_config:\n  include: {}\n")
        with pytest.raises(ValueError, match=r"pkg_manifest\.origin"):
            _load_spec(str(tmp_path / "pkgs" / "pkg" / "config.yml"))

    def test_mapping_version_rejected(self, tmp_path):
        write(tmp_path, "pkg", "pkg_manifest:\n  name: x\n  origin: o\n  version:\n    a: 1\nbuild_config:\n  include: {}\n")
        with pytest.raises(TypeError, match=r"pkg_manifest\.version"):
            _load_spec(str(tmp_path / "pkgs" / "pkg" / "config.yml"))

    def test_bad_redistribute_abi_key_names_it(self, tmp_path):
        broken = REDISTRIBUTE_SPEC.replace("FreeBSD-15-amd64: \"1.4.7\"", "FreeBSD-16-riscv: \"1.4.7\"")
        write(tmp_path, "btop", broken)
        with pytest.raises(ValueError, match=r"redistribute\.version\.FreeBSD-16-riscv"):
            _load_spec(str(tmp_path / "pkgs" / "btop" / "config.yml"))

    def test_both_manifest_and_redistribute_rejected(self, tmp_path):
        both = BUILD_SPEC + "\nredistribute:\n  name: x\n  version:\n    FreeBSD-15-amd64: \"1.0\"\n"
        write(tmp_path, "pkg", both)
        with pytest.raises(ValueError, match="both pkg_manifest and redistribute"):
            _load_spec(str(tmp_path / "pkgs" / "pkg" / "config.yml"))

    def test_missing_build_config_include_rejected(self, tmp_path):
        write(tmp_path, "pkg", "pkg_manifest:\n  name: x\n  origin: o\n  version: 1.0\nbuild_config:\n  src_repo: 'https://github.com/a/b'\n")
        with pytest.raises(TypeError, match=r"build_config\.include"):
            _load_spec(str(tmp_path / "pkgs" / "pkg" / "config.yml"))

    def test_mapping_name_rejected(self, tmp_path):
        write(tmp_path, "pkg", "pkg_manifest:\n  name:\n    a: 1\n  origin: o\n  version: 1.0\nbuild_config:\n  include: {}\n")
        with pytest.raises(TypeError, match=r"pkg_manifest\.name"):
            _load_spec(str(tmp_path / "pkgs" / "pkg" / "config.yml"))

    def test_pkg_service_rejected(self, tmp_path):
        with_service = BUILD_SPEC + "\npkg_service:\n  template: default\n  vars:\n    COMMAND: /usr/local/bin/blocky\n"
        write(tmp_path, "pkg", with_service)
        with pytest.raises(ValueError, match="pkg_service"):
            _load_spec(str(tmp_path / "pkgs" / "pkg" / "config.yml"))

    def test_empty_repo_config_raises_type_error_not_attribute_error(self, tmp_path):
        write(tmp_path, "blocky", BUILD_SPEC, repo_config="\n")
        with pytest.raises(TypeError, match="not a mapping"):
            build_matrix(packages=None, pkgs_dir=str(tmp_path / "pkgs"), repo_config=str(tmp_path / "config.yml"))


class TestDump:
    def test_dump_scalars(self, tmp_path):
        write(tmp_path, "blocky", BUILD_SPEC)
        config = str(tmp_path / "pkgs" / "blocky" / "config.yml")
        assert dump(config, "pkg_manifest.name") == "blocky"
        assert dump(config, "pkg_manifest.version") == "0.34.0"
        assert dump(config, "build_config.src_repo") == "https://github.com/0xERR0R/blocky"

    def test_dump_validates_before_read(self, tmp_path):
        write(tmp_path, "pkg", "pkg_manifest:\n  name: x\nbuild_config:\n  include: {}\n")
        with pytest.raises(ValueError, match=r"pkg_manifest\.version"):
            dump(str(tmp_path / "pkgs" / "pkg" / "config.yml"), "pkg_manifest.name")

    def test_dump_missing_path(self, tmp_path):
        write(tmp_path, "blocky", BUILD_SPEC)
        with pytest.raises(ValueError, match="pkg_manifest.nope"):
            dump(str(tmp_path / "pkgs" / "blocky" / "config.yml"), "pkg_manifest.nope")

    def test_dump_mapping_path_rejected(self, tmp_path):
        write(tmp_path, "blocky", BUILD_SPEC)
        with pytest.raises(TypeError, match="not a scalar"):
            dump(str(tmp_path / "pkgs" / "blocky" / "config.yml"), "pkg_manifest")


class TestBuildMatrix:
    def test_matrix_matches_old_shape(self, tmp_path):
        write(tmp_path, "blocky", BUILD_SPEC)
        write(tmp_path, "btop", REDISTRIBUTE_SPEC)
        (tmp_path / "pkgs" / "blocky" / "build.sh").touch()

        matrix = build_matrix(packages=None, pkgs_dir=str(tmp_path / "pkgs"), repo_config=str(tmp_path / "config.yml"))

        assert matrix == {
            "pkg_name": ["blocky"],
            "arch": ["amd64"],
            "abi": [15],
            "include": [{"go": "1.26", "pkg_name": "blocky"}],
        }
        assert json.dumps(matrix, separators=(",", ":")) == (
            '{"pkg_name":["blocky"],"arch":["amd64"],"abi":[15],'
            '"include":[{"go":"1.26","pkg_name":"blocky"}]}'
        )

    def test_matrix_with_explicit_packages(self, tmp_path):
        write(tmp_path, "blocky", BUILD_SPEC)
        write(tmp_path, "btop", REDISTRIBUTE_SPEC)
        (tmp_path / "pkgs" / "blocky" / "build.sh").touch()

        matrix = build_matrix(packages=["btop"], pkgs_dir=str(tmp_path / "pkgs"), repo_config=str(tmp_path / "config.yml"))

        assert matrix["pkg_name"] == ["btop"]
        assert matrix["include"] == [{"pkg_name": "btop"}]

    def test_matrix_skips_packages_without_config(self, tmp_path):
        write(tmp_path, "blocky", BUILD_SPEC)
        (tmp_path / "pkgs" / "blocky" / "build.sh").touch()
        (tmp_path / "pkgs" / "ghost").mkdir()
        (tmp_path / "pkgs" / "ghost" / "build.sh").touch()

        matrix = build_matrix(packages=None, pkgs_dir=str(tmp_path / "pkgs"), repo_config=str(tmp_path / "config.yml"))

        assert matrix["pkg_name"] == ["blocky", "ghost"]
        assert matrix["include"] == [{"go": "1.26", "pkg_name": "blocky"}]

    def test_matrix_validates_repo_config(self, tmp_path):
        write(tmp_path, "blocky", BUILD_SPEC, repo_config="pkg-repo: {}\n")
        with pytest.raises(TypeError, match="pkg-repo"):
            build_matrix(packages=None, pkgs_dir=str(tmp_path / "pkgs"), repo_config=str(tmp_path / "config.yml"))
