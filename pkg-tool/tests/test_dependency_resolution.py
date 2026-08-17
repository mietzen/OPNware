"""Repo-seam regression test (ticket #270): every opnware/* dependency declared
by a plugin spec must be satisfiable by a package version the repo publishes.

check-updates skips plugin specs (they have no remote version source), so the
plugin dependency graph is unguarded in CI. This test closes that gap by
loading the real specs under pkgs/ and asserting each opnware/* dep resolves
against the versions the repo actually publishes.
"""

import re
from pathlib import Path

import pytest

from pkg_tool import _load_spec

PKGS_DIR = Path(__file__).resolve().parents[2] / "pkgs"

_REVISION_SUFFIX = re.compile(r"_[0-9]+$")
_CONSTRAINT = re.compile(r"^\s*(>=|<=|>|<|==|=)?\s*([0-9][0-9A-Za-z._-]*)\s*$")


def _version_tuple(version):
    """Split a version into comparable numeric components, dropping a FreeBSD
    _N revision suffix (package-only changes, not a version difference)."""
    base = _REVISION_SUFFIX.sub("", version)
    return tuple(int(part) for part in base.split("."))


def _compare(a, b):
    """Compare two versions after normalizing FreeBSD _N revision suffixes."""
    a_parts, b_parts = _version_tuple(a), _version_tuple(b)
    for x, y in zip(a_parts, b_parts):
        if x != y:
            return -1 if x < y else 1
    return (len(a_parts) > len(b_parts)) - (len(a_parts) < len(b_parts))


def _satisfies(published, constraint):
    """True if `published` satisfies a comma-separated version constraint
    (e.g. '>=2.11.4, <3.0.0')."""
    for part in constraint.split(","):
        match = _CONSTRAINT.match(part)
        if not match:
            raise ValueError(f"unsupported version constraint: {constraint!r}")
        operator, version = match.group(1) or "==", match.group(2)
        order = _compare(published, version)
        if operator == ">=" and order < 0:
            return False
        if operator == "<=" and order > 0:
            return False
        if operator == ">" and order <= 0:
            return False
        if operator == "<" and order >= 0:
            return False
        if operator in ("==", "=") and order != 0:
            return False
    return True


def _published_versions(pkgs_dir):
    """origin -> published version for every opnware/* package spec."""
    published = {}
    for config in sorted(pkgs_dir.glob("*/config.yml")):
        spec = _load_spec(str(config))
        manifest = spec.get("pkg_manifest")
        if not manifest:
            continue  # redistribute-only specs publish no opnware origin
        origin = manifest.get("origin", "")
        if origin.startswith("opnware/"):
            published[origin] = str(manifest["version"])
    return published


def _plugin_opnware_deps(pkgs_dir):
    """(plugin, dep_name, origin, constraint) for every opnware/* dep of a plugin spec."""
    deps = []
    for config in sorted(pkgs_dir.glob("*/config.yml")):
        spec = _load_spec(str(config))
        if not spec.get("plugin"):
            continue
        plugin = config.parent.name
        for dep_name, dep in (spec.get("pkg_manifest", {}).get("deps") or {}).items():
            origin = dep.get("origin", "")
            if origin.startswith("opnware/"):
                deps.append((plugin, dep_name, origin, dep.get("version", "")))
    return deps


def test_plugin_opnware_deps_are_satisfiable_by_published_versions():
    deps = _plugin_opnware_deps(PKGS_DIR)
    assert deps, f"no opnware/* plugin dependencies found under {PKGS_DIR}"
    published = _published_versions(PKGS_DIR)
    unsatisfied = []
    for plugin, dep_name, origin, constraint in deps:
        available = published.get(origin)
        if available is None:
            unsatisfied.append(
                f"{plugin} depends on {origin} ({constraint}) but no such package is published"
            )
        elif not _satisfies(available, constraint):
            unsatisfied.append(
                f"{plugin} requires {origin} {constraint}, but the published version is {available}"
            )
    assert not unsatisfied, "unsatisfiable plugin dependencies:\n" + "\n".join(unsatisfied)


class TestVersionConstraint:
    def test_simple_lower_bound(self):
        assert _satisfies("2.11.4", ">=2.11.4")
        assert not _satisfies("2.11.3", ">=2.11.4")

    def test_comma_separated_bounds(self):
        assert _satisfies("2.11.4", ">=2.11.4, <3.0.0")
        assert _satisfies("2.99.0", ">=2.11.4, <3.0.0")
        assert not _satisfies("3.0.0", ">=2.11.4, <3.0.0")
        assert not _satisfies("2.11.3", ">=2.11.4, <3.0.0")

    def test_revision_suffix_normalized(self):
        assert _satisfies("0.56.0_2", ">=0.56.0")
        assert _satisfies("0.56.0_2", ">=0.56.0, <0.57.0")

    def test_unsupported_constraint_raises(self):
        with pytest.raises(ValueError, match="unsupported version constraint"):
            _satisfies("1.0.0", "~1.0")
