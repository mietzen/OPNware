"""Source-seam tests for the os-caddy flat editor (tickets: editor tree).

The tree helper and save script are PHP (no PHP harness in this repo), so the
pre-agreed seam for these invariants is the shipped source itself: the tree is
flat (Caddyfile + conf.d/*.caddy only, seeded with the native non-recursive
import glob), and the seed must not contain a fragile env placeholder that
breaks validation when CADDY_LOG_LEVEL is empty (both found on hardware).
"""

from pathlib import Path

EDITOR_TREE = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/editor_tree.php")
EDITOR_SAVE = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/editor_save.php")
EDITOR_CONTROLLER = Path(
    "pkgs/os-caddy-advanced/src/opnsense/mvc/app/controllers/OPNsense/CaddyAdvanced/Api/EditorController.php"
)

def test_seed_uses_flat_confd_glob():
    src = EDITOR_TREE.read_text()
    assert "import conf.d/*.caddy" in src


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
    assert "array_diff(editor_tree_walk_files(BASE), $staged)" in src


def test_single_file_save_clears_stale_staging_before_staging():
    # A failed tree op (add/copy/move/delete) leaves the .complete marker plus
    # a stale full-tree copy in the staging dir — editor_save.php only cleans
    # staging on success. A single-file save must clear that stale staging
    # first, or the stale copy is applied as the intended tree, reverting
    # newer edits (ticket #244).
    src = EDITOR_CONTROLLER.read_text()
    assert "$this->clearStaging();" in src
    # The clear must happen before the single-file stage write, not after.
    save_block = src[src.index("public function saveAction"):]
    assert save_block.index("$this->clearStaging();") < save_block.index(
        "$staged = self::STAGING_DIR . '/' . $rel;"
    )


def test_failed_save_cycle_cleans_staging():
    # The controller-side clear neutralizes the WebUI path; a direct configd
    # editor-save against leftover staging must also be safe — so the save
    # script itself must clean staging on every failure, not just success.
    src = EDITOR_SAVE.read_text()
    complete_block = src[src.index("function editor_complete"):]
    assert "if ($result !== 'ok') {" in complete_block
    assert "editor_rmtree(STAGING_DIR);" in complete_block


def test_editor_controller_enforces_post_method():
    src = EDITOR_CONTROLLER.read_text()
    for action in ["public function saveAction", "public function addAction", "public function deleteAction", "private function copyOrMove"]:
        block = src[src.index(action):]
        assert "$this->request->isPost()" in block[:200]
        assert "gettext('Method Not Allowed')" in block[:200]


def test_caddy_modules_validates_go_import_paths():
    modules_script = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/modules.php").read_text()
    assert "is_valid_module_path" in modules_script
    assert "invalid declared module path" in modules_script

    modules_ctrl = Path("pkgs/os-caddy-advanced/src/opnsense/mvc/app/controllers/OPNsense/CaddyAdvanced/Api/ModulesController.php").read_text()
    assert "isValidModulePath" in modules_ctrl
    assert "public function setAction" in modules_ctrl
    assert "isValidModulePath($mod)" in modules_ctrl
    assert "$this->request->isPost()" in modules_ctrl


def test_caddy_modules_status_separates_fingerprints():
    modules_ctrl = Path("pkgs/os-caddy-advanced/src/opnsense/mvc/app/controllers/OPNsense/CaddyAdvanced/Api/ModulesController.php").read_text()
    assert "$data['binary_fingerprint']" in modules_ctrl
    assert "$data['moduleset_fingerprint']" in modules_ctrl
    assert "caddy-docker-proxy" in modules_ctrl

    modules_volt = Path("pkgs/os-caddy-advanced/src/opnsense/mvc/app/views/OPNsense/CaddyAdvanced/modules.volt").read_text()
    assert "status-binary-fingerprint" in modules_volt
    assert "status-moduleset-fingerprint" in modules_volt
    assert "Installed Modules" not in modules_volt

    general_volt = Path("pkgs/os-caddy-advanced/src/opnsense/mvc/app/views/OPNsense/CaddyAdvanced/general.volt").read_text()
    assert "data.modules.map" in general_volt
    assert "'<code>' + $('<div>').text(m).html() + '</code>'" in general_volt

    status_php = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/status.php").read_text()
    assert "Non-standard modules:" in status_php


def test_seed_creates_example_caddy_on_port_8080():
    src = EDITOR_TREE.read_text()
    assert "$exampleFile = $base . '/conf.d/example.caddy';" in src
    assert ":8080 {" in src
    assert 'Hello from Caddy Advanced on OPNsense!' in src
    # Must be inside initial if (!is_file($caddyfile)) block to prevent recreating when deleted
    assert src.index("$exampleFile = $base . '/conf.d/example.caddy';") > src.index("if (!is_file($caddyfile)) {")
    assert src.index("$exampleFile = $base . '/conf.d/example.caddy';") < src.index("} else {")
    assert "$envfile = $base . '/env';" in src


def test_rc_script_ensures_envfile_in_precmd():
    rc_script = Path("pkgs/os-caddy-advanced/src/usr/local/etc/rc.d/caddy").read_text()
    assert "caddy_precmd()" in rc_script
    assert "_envfile=" in rc_script
    assert 'chmod 600' in rc_script or 'install -m 600' in rc_script


def test_dockerproxy_syncs_polling_and_service_tasks():
    dp_script = Path("pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/dockerproxy.php").read_text()
    assert "'CADDY_DOCKER_POLLING_INTERVAL'" in dp_script
    assert "'CADDY_DOCKER_PROXY_SERVICE_TASKS'" in dp_script
    assert "$rows['CADDY_DOCKER_POLLING_INTERVAL']" in dp_script
    assert "$rows['CADDY_DOCKER_PROXY_SERVICE_TASKS']" in dp_script

