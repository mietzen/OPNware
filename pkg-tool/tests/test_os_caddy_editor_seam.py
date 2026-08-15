"""Source-seam tests for the os-caddy flat editor (tickets: editor tree).

The tree helper and save script are PHP (no PHP harness in this repo), so the
pre-agreed seam for these invariants is the shipped source itself: the tree is
flat (Caddyfile + conf.d/*.caddy only, seeded with the native non-recursive
import glob), and the seed must not contain a fragile env placeholder that
breaks validation when CADDY_LOG_LEVEL is empty (both found on hardware).
"""

from pathlib import Path

EDITOR_TREE = Path("pkgs/os-caddy/src/opnsense/scripts/OPNsense/Caddy/editor_tree.php")
EDITOR_SAVE = Path("pkgs/os-caddy/src/opnsense/scripts/OPNsense/Caddy/editor_save.php")


def test_seed_uses_flat_confd_glob():
    src = EDITOR_TREE.read_text()
    assert '"import conf.d/*.caddy\\n"' in src


def test_no_generated_import_index():
    src = EDITOR_TREE.read_text()
    # Assert the machinery is gone, not the words: the legacy-seed migration
    # regex legitimately mentions the old file.
    assert "editor_tree_write_imports" not in src
    assert "EDITOR_TREE_IMPORTS" not in src
    assert "import ../' . $rel" not in src


def test_seed_has_no_fragile_log_level_placeholder():
    src = EDITOR_TREE.read_text()
    assert "level {$CADDY_LOG_LEVEL}" not in src


def test_tree_accepts_flat_paths_only():
    src = EDITOR_TREE.read_text()
    # Nested paths under conf.d are rejected: the import glob is non-recursive.
    assert "strpos($rel, '/', 7) !== false" in src


def test_save_engine_handles_complete_tree_deletions():
    src = EDITOR_SAVE.read_text()
    assert "COMPLETE_STAGING_MARKER" in src
    assert "array_diff(editor_tree_files(BASE), $staged)" in src
