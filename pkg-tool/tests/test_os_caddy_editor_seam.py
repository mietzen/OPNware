"""Source-seam tests for the os-caddy recursive editor (tickets: recursive tree).

The tree helper and save script are PHP (no PHP harness in this repo), so the
pre-agreed seam for these invariants is the shipped source itself: the
generated import index must be relative to .opnware (../conf.d/...) and the
seed must not contain a fragile env placeholder that breaks validation when
CADDY_LOG_LEVEL is empty (both found on hardware).
"""

from pathlib import Path

EDITOR_TREE = Path("pkgs/os-caddy/src/opnsense/scripts/OPNsense/Caddy/editor_tree.php")
EDITOR_SAVE = Path("pkgs/os-caddy/src/opnsense/scripts/OPNsense/Caddy/editor_save.php")


def test_generated_imports_are_relative_to_opnware():
    src = EDITOR_TREE.read_text()
    assert "'import ../' . $rel" in src


def test_seed_has_no_fragile_log_level_placeholder():
    src = EDITOR_TREE.read_text()
    assert "level {$CADDY_LOG_LEVEL}" not in src
    assert "import .opnware/imports.caddy" in src


def test_save_engine_handles_complete_tree_deletions():
    src = EDITOR_SAVE.read_text()
    assert "COMPLETE_STAGING_MARKER" in src
    assert "array_diff(editor_tree_files(BASE), $staged)" in src
