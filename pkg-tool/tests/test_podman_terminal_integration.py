"""Tests for os-podman interactive XTerm.js terminal integration."""

import asyncio
import base64
import hashlib
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
PODMAN_SRC = ROOT_DIR / "pkgs" / "os-podman" / "src"


def test_xterm_assets_packaged():
    js_dir = PODMAN_SRC / "opnsense" / "www" / "js" / "vendor" / "xterm"
    css_dir = PODMAN_SRC / "opnsense" / "www" / "css" / "vendor" / "xterm"

    assert (js_dir / "xterm.js").exists()
    assert (js_dir / "addon-fit.js").exists()
    assert (css_dir / "xterm.css").exists()

    xterm_js = (js_dir / "xterm.js").read_text()
    assert "Terminal" in xterm_js

    fit_js = (js_dir / "addon-fit.js").read_text()
    assert "FitAddon" in fit_js


def test_lighttpd_terminal_fragment():
    conf_file = PODMAN_SRC / "etc" / "lighttpd_webgui" / "conf.d" / "50-podman-terminal.conf"
    assert conf_file.exists()

    content = conf_file.read_text()
    assert 'server.modules += ( "mod_proxy" )' in content
    assert '"^/api/podman/terminal/ws"' in content
    assert '"upgrade" => "enable"' in content
    assert '"host" => "127.0.0.1"' in content
    assert '"port" => 7681' in content


def test_terminal_daemon_script_and_rc_integration():
    daemon_script = PODMAN_SRC / "opnsense" / "scripts" / "OPNsense" / "Podman" / "terminal_daemon.py"
    assert daemon_script.exists()
    assert daemon_script.stat().st_mode & 0o111, "terminal_daemon.py must be executable"

    rc_script = PODMAN_SRC / "usr" / "local" / "etc" / "rc.d" / "podman-service"
    assert rc_script.exists()
    rc_content = rc_script.read_text()

    assert "terminal_daemon=" in rc_content
    assert "terminal.pid" in rc_content
    assert "7681" in rc_content


def test_dashboard_volt_terminal_integration():
    volt_file = PODMAN_SRC / "opnsense" / "mvc" / "app" / "views" / "OPNsense" / "Podman" / "dashboard.volt"
    assert volt_file.exists()

    content = volt_file.read_text()
    assert "/ui/css/vendor/xterm/xterm.css" in content
    assert "/ui/js/vendor/xterm/xterm.js" in content
    assert "/ui/js/vendor/xterm/addon-fit.js" in content
    assert "xterm-terminal-container" in content
    assert "connectTerminalWs" in content
    assert "/api/podman/terminal/ws" in content


def test_terminal_daemon_websocket_helpers():
    # Import functions directly from terminal_daemon
    sys.path.insert(0, str(PODMAN_SRC / "opnsense" / "scripts" / "OPNsense" / "Podman"))
    try:
        import terminal_daemon
        import tempfile
        import os

        # 1. Test accept key computation
        test_key = "dGhlIHNhbXBsZSBub25jZQ=="
        expected_accept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        assert terminal_daemon.compute_ws_accept(test_key) == expected_accept

        # 2. Test frame encoding (binary default)
        payload = b"hello world"
        frame = terminal_daemon.encode_ws_frame(payload, opcode=terminal_daemon.OPCODE_BIN)
        assert frame[0] == 0x82  # FIN + binary opcode
        assert frame[1] == len(payload)
        assert frame[2:] == payload

        # 3. Test large frame encoding (126 extended length)
        large_payload = b"A" * 300
        large_frame = terminal_daemon.encode_ws_frame(large_payload, opcode=terminal_daemon.OPCODE_BIN)
        assert large_frame[0] == 0x82
        assert large_frame[1] == 126
        assert len(large_frame) == 2 + 2 + 300

        # 4. Test auth session validation
        with tempfile.TemporaryDirectory() as sdir:
            sess_file_auth = Path(sdir) / "sess_validauth123"
            sess_file_auth.write_text("user_name|s:5:\"admin\";")

            sess_file_csrf_only = Path(sdir) / "sess_csrfonly456"
            sess_file_csrf_only.write_text("csrf|s:32:\"random_token_here_not_logged_in\";")

            os.environ["OPNSENSE_SESSION_DIR"] = sdir

            # Unauthenticated without cookie
            assert terminal_daemon.is_authenticated_session("") is False
            assert terminal_daemon.is_authenticated_session("other=value") is False

            # Invalid session token (missing file)
            assert terminal_daemon.is_authenticated_session("PHPSESSID=missingtoken") is False

            # Unauthenticated session with only CSRF token
            assert terminal_daemon.is_authenticated_session("PHPSESSID=csrfonly456") is False

            # Authenticated session token
            assert terminal_daemon.is_authenticated_session("PHPSESSID=validauth123") is True

        # 5. Test TerminalSession close and reap logic
        session = terminal_daemon.TerminalSession("dummy-cid", "/bin/sh")
        session.master_fd = None
        session.pid = None
        session.close()
        assert session.closed is True
    finally:
        sys.path.pop(0)
