"""Tests for os-terminal plugin and bash package integration."""

import os
import sys
import tempfile
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT_DIR = Path(__file__).resolve().parents[2]
TERMINAL_SRC = ROOT_DIR / "pkgs" / "os-terminal" / "src"
BASH_PKG = ROOT_DIR / "pkgs" / "bash"


def test_bash_redistribute_config():
    config_file = BASH_PKG / "config.yml"
    assert config_file.exists()
    content = config_file.read_text()
    assert "name: bash" in content
    assert 'FreeBSD-15-amd64: "5.3.15"' in content
    assert "http://pkg.freebsd.org" in content

    build_sh = BASH_PKG / "build.sh"
    assert build_sh.exists()
    assert build_sh.stat().st_mode & 0o111


def test_os_terminal_config_and_structure():
    config_file = ROOT_DIR / "pkgs" / "os-terminal" / "config.yml"
    assert config_file.exists()
    content = config_file.read_text()
    assert "name: terminal" in content
    assert "origin: opnware/os-terminal" in content
    assert 'version: 0.1.0' in content

    build_sh = ROOT_DIR / "pkgs" / "os-terminal" / "build.sh"
    assert build_sh.exists()
    assert build_sh.stat().st_mode & 0o111


def test_xterm_assets_packaged():
    js_dir = TERMINAL_SRC / "opnsense" / "www" / "js" / "vendor" / "terminal"
    css_dir = TERMINAL_SRC / "opnsense" / "www" / "css" / "vendor" / "terminal"

    assert (js_dir / "xterm.js").exists()
    assert (js_dir / "addon-fit.js").exists()
    assert (css_dir / "xterm.css").exists()

    xterm_js = (js_dir / "xterm.js").read_text()
    assert "Terminal" in xterm_js

    fit_js = (js_dir / "addon-fit.js").read_text()
    assert "FitAddon" in fit_js


def test_lighttpd_terminal_proxy_fragment():
    conf_file = TERMINAL_SRC / "etc" / "lighttpd_webgui" / "conf.d" / "50-terminal.conf"
    assert conf_file.exists()

    content = conf_file.read_text()
    assert 'server.modules += ( "mod_proxy" )' in content
    assert '"^/api/terminal/ws"' in content
    assert '"upgrade" => "enable"' in content
    assert '"host" => "127.0.0.1"' in content
    assert '"port" => 7682' in content


def test_rc_script_and_templates():
    rc_script = TERMINAL_SRC / "usr" / "local" / "etc" / "rc.d" / "terminal-service"
    assert rc_script.exists()
    assert rc_script.stat().st_mode & 0o111
    rc_content = rc_script.read_text()

    assert "terminal_daemon=" in rc_content
    assert "terminal_service.pid" in rc_content
    assert "7682" in rc_content

    targets = TERMINAL_SRC / "opnsense" / "service" / "templates" / "OPNsense" / "Terminal" / "+TARGETS"
    assert targets.exists()
    assert "rc.conf.d:/etc/rc.conf.d/terminal_service" in targets.read_text()

    rc_conf_d = TERMINAL_SRC / "opnsense" / "service" / "templates" / "OPNsense" / "Terminal" / "rc.conf.d"
    assert rc_conf_d.exists()
    assert "terminal_service_enable" in rc_conf_d.read_text()


def test_mvc_model_and_controllers():
    model_xml = TERMINAL_SRC / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Terminal" / "Terminal.xml"
    assert model_xml.exists()
    assert "<mount>//OPNsense/terminal</mount>" in model_xml.read_text()

    model_php = TERMINAL_SRC / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Terminal" / "Terminal.php"
    assert model_php.exists()

    menu_xml = TERMINAL_SRC / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Terminal" / "Menu" / "Menu.xml"
    assert menu_xml.exists()
    assert 'url="/ui/terminal"' in menu_xml.read_text()

    acl_xml = TERMINAL_SRC / "opnsense" / "mvc" / "app" / "models" / "OPNsense" / "Terminal" / "ACL" / "ACL.xml"
    assert acl_xml.exists()
    assert "<pattern>ui/terminal</pattern>" in acl_xml.read_text()

    ctrl_dir = TERMINAL_SRC / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Terminal"
    assert (ctrl_dir / "IndexController.php").exists()
    assert (ctrl_dir / "Api" / "ServiceController.php").exists()
    assert (ctrl_dir / "Api" / "SettingsController.php").exists()
    assert (ctrl_dir / "Api" / "TerminalController.php").exists()


def test_terminal_daemon_helpers_and_auth():
    sys.modules.pop("terminal_daemon", None)
    sys.path.insert(0, str(TERMINAL_SRC / "opnsense" / "scripts" / "OPNsense" / "Terminal"))
    try:
        import terminal_daemon

        # 1. Accept key computation
        test_key = "dGhlIHNhbXBsZSBub25jZQ=="
        expected_accept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        assert terminal_daemon.compute_ws_accept(test_key) == expected_accept

        # 2. Frame encoding
        payload = b"test host terminal"
        frame = terminal_daemon.encode_ws_frame(payload, opcode=terminal_daemon.OPCODE_BIN)
        assert frame[0] == 0x82
        assert frame[1] == len(payload)
        assert frame[2:] == payload

        # 3. Auth extraction
        with tempfile.TemporaryDirectory() as sdir:
            sess_file_root = Path(sdir) / "sess_root123"
            sess_file_root.write_text('user_name|s:4:"root";')

            sess_file_admin = Path(sdir) / "sess_admin456"
            sess_file_admin.write_text('Username|s:5:"admin";')

            sess_file_csrf = Path(sdir) / "sess_csrfonly"
            sess_file_csrf.write_text('csrf|s:32:"random_token";')

            os.environ["OPNSENSE_SESSION_DIR"] = sdir

            assert terminal_daemon.extract_authenticated_user("") == ""
            assert terminal_daemon.extract_authenticated_user("PHPSESSID=missing") == ""
            assert terminal_daemon.extract_authenticated_user("PHPSESSID=csrfonly") == ""
            assert terminal_daemon.extract_authenticated_user("PHPSESSID=root123") == "root"
            assert terminal_daemon.extract_authenticated_user("PHPSESSID=admin456") == "admin"

        # 4. Shell resolution logic
        assert terminal_daemon.resolve_shell("nonexistent_user", default_shell_setting="sh") == "/bin/sh"
        assert terminal_daemon.resolve_shell("root", default_shell_setting="sh") == "/bin/sh"

        # 5. HostTerminalSession close
        session = terminal_daemon.HostTerminalSession("root", "/bin/sh")
        session.master_fd = None
        session.pid = None
        session.close()
        assert session.closed is True
    finally:
        sys.path.pop(0)


def test_settings_controller_login_shell_sync():
    ctrl_file = TERMINAL_SRC / "opnsense" / "mvc" / "app" / "controllers" / "OPNsense" / "Terminal" / "Api" / "SettingsController.php"
    content = ctrl_file.read_text()
    assert "syncUserShell" in content
    assert "local_user_set" in content
    assert "default_shell" in content
    assert "setAction" in content

