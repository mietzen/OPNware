"""Source-seam tests for os-caddy-advanced module deduplication (issue #372)."""

from pathlib import Path

MODULES_CONTROLLER = Path(
    "pkgs/os-caddy-advanced/src/opnsense/mvc/app/controllers/OPNsense/CaddyAdvanced/Api/ModulesController.php"
)
MODULES_VOLT = Path(
    "pkgs/os-caddy-advanced/src/opnsense/mvc/app/views/OPNsense/CaddyAdvanced/modules.volt"
)


def test_modules_controller_deduplicates_in_get_model_nodes():
    src = MODULES_CONTROLLER.read_text()
    assert "array_unique" in src
    get_nodes_block = src[src.index("function getModelNodes"):src.index("function resultOr")]
    assert "array_unique" in get_nodes_block


def test_modules_controller_deduplicates_in_set_action():
    src = MODULES_CONTROLLER.read_text()
    set_action_block = src[src.index("public function setAction"):src.index("public function rebuildAction")]
    assert "$unique = [];" in set_action_block
    assert "!in_array($mod, $unique, true)" in set_action_block


def test_modules_volt_deduplicates_loaded_modules():
    src = MODULES_VOLT.read_text()
    load_modules_block = src[src.index("function loadModules()"):src.index("function appendLog")]
    assert "modules.indexOf(mod) === -1" in load_modules_block
