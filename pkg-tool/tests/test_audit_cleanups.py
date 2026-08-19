"""Invariants for tickets #281 to #285 cleanups."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def test_editor_save_does_not_duplicate_tree_helpers():
    save_php = (
        REPO_ROOT
        / "pkgs/os-caddy-advanced/src/opnsense/scripts/OPNsense/CaddyAdvanced/editor_save.php"
    ).read_text()
    assert "function editor_safe_rel" not in save_php
    assert "function editor_under_base" not in save_php
    assert "function editor_tree_files" not in save_php
    assert "editor_tree_walk_files" in save_php


def test_config_save_has_no_manual_structural_parser():
    config_save_php = (
        REPO_ROOT
        / "pkgs/os-homer/src/opnsense/scripts/OPNsense/Homer/config_save.php"
    ).read_text()
    assert "config_structural_check" not in config_save_php
    assert "parser_warning" not in config_save_php


def test_actions_caddyadvanced_modules_has_no_dead_start_hook():
    actions_conf = (
        REPO_ROOT
        / "pkgs/os-caddy-advanced/src/opnsense/service/conf/actions.d/actions_caddyadvanced-modules.conf"
    ).read_text()
    assert "[start-hook]" not in actions_conf


def test_service_hooks_initialize_services_array():
    caddy_inc = (
        REPO_ROOT
        / "pkgs/os-caddy-advanced/src/etc/inc/plugins.inc.d/caddyadvanced.inc"
    ).read_text()
    homer_inc = (
        REPO_ROOT
        / "pkgs/os-homer/src/etc/inc/plugins.inc.d/homer.inc"
    ).read_text()
    assert "$services = array();" in caddy_inc
    assert "$services = array();" in homer_inc


def test_caddyadvanced_xml_has_no_as_list_on_text_field():
    xml = (
        REPO_ROOT
        / "pkgs/os-caddy-advanced/src/opnsense/mvc/app/models/OPNsense/CaddyAdvanced/CaddyAdvanced.xml"
    ).read_text()
    assert "<AsList>" not in xml


def test_no_stale_os_caddy_docblock_headers():
    src_dir = REPO_ROOT / "pkgs/os-caddy-advanced/src"
    for path in src_dir.rglob("*"):
        if path.suffix in [".php", ".volt"]:
            content = path.read_text()
            assert "OPNware os-caddy —" not in content, f"Found stale docblock in {path}"


def test_status_tables_aligned_across_plugins():
    homer_general = (REPO_ROOT / "pkgs/os-homer/src/opnsense/mvc/app/views/OPNsense/Homer/general.volt").read_text()
    caddy_general = (REPO_ROOT / "pkgs/os-caddy-advanced/src/opnsense/mvc/app/views/OPNsense/CaddyAdvanced/general.volt").read_text()
    caddy_modules = (REPO_ROOT / "pkgs/os-caddy-advanced/src/opnsense/mvc/app/views/OPNsense/CaddyAdvanced/modules.volt").read_text()
    podman_general = (REPO_ROOT / "pkgs/os-podman/src/opnsense/mvc/app/views/OPNsense/Podman/general.volt").read_text()

    for content, table_id in [
        (homer_general, "tbl_homer_status"),
        (caddy_general, "tbl_caddy_status"),
        (caddy_modules, "tbl_caddy_modules_status"),
        (podman_general, "tbl_podman_status"),
    ]:
        assert f'id="{table_id}"' in content
        assert '<table class="table table-striped table-condensed"' in content
        assert '<thead>' in content
        assert '<tr>' in content
        assert '<th colspan="2"><b>' in content
        assert '<td style="width: 250px;">' in content
        assert 'class="content-box" style="margin-bottom: 20px;"' in content
