"""Tests for the monaco codicon-font extraction codemod (ticket #272).

The codemod is Python (runnable in this repo's pytest harness), so the seam is
the codemod itself: it must decode the base64-inlined codicon font from
monaco's min editor.main.css into a same-origin .ttf and rewrite the @font-face
src: to reference it relatively (OPNsense CSP has no font-src, so data: font
URLs are blocked). Plus a source-seam test asserting build.sh wires the codemod
in after the CSP worker patch.
"""

import base64
import subprocess
import sys
from pathlib import Path

import pytest

CODEMOD = Path("pkgs/monaco-editor/src/extract-codicon-font.py")
BUILD_SH = Path("pkgs/monaco-editor/build.sh")

# TTF magic (0x0001) + numTables — enough for the codemod's magic check.
TTF_BYTES = b"\x00\x01\x00\x00\x00\x0d\x00\x80"
TTF_B64 = base64.b64encode(TTF_BYTES).decode("ascii")


def run_codemod(vendor_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CODEMOD), str(vendor_dir)],
        capture_output=True,
        text=True,
    )


def make_vendor(tmp_path: Path) -> Path:
    """Build a fake vendor tree with a pristine min editor.main.css."""
    vendor = tmp_path / "vendor"
    css_dir = vendor / "monaco/vs/editor"
    css_dir.mkdir(parents=True)
    css = (
        "@font-face{font-family:codicon;font-display:block;"
        f"src:url(data:font/ttf;base64,{TTF_B64})" + "}"
        ".monaco-editor{color:red}"
    )
    (css_dir / "editor.main.css").write_text(css)
    return vendor


def test_extracts_ttf_and_rewrites_src(tmp_path):
    vendor = make_vendor(tmp_path)
    result = run_codemod(vendor)
    assert result.returncode == 0, result.stderr

    ttf = vendor / "monaco/vs/base/browser/ui/codicons/codicon/codicon.ttf"
    assert ttf.read_bytes() == TTF_BYTES
    assert ttf.stat().st_mode & 0o777 == 0o644

    css = (vendor / "monaco/vs/editor/editor.main.css").read_text()
    assert "data:font/ttf" not in css
    assert (
        "src:url(../base/browser/ui/codicons/codicon/codicon.ttf)" in css
    )
    # Unrelated CSS is untouched.
    assert ".monaco-editor{color:red}" in css


def test_idempotent_second_run_is_noop(tmp_path):
    vendor = make_vendor(tmp_path)
    assert run_codemod(vendor).returncode == 0
    ttf_before = (vendor / "monaco/vs/base/browser/ui/codicons/codicon/codicon.ttf").read_bytes()
    css_before = (vendor / "monaco/vs/editor/editor.main.css").read_text()

    result = run_codemod(vendor)
    assert result.returncode == 0, result.stderr
    assert "already patched" in result.stdout
    assert (vendor / "monaco/vs/base/browser/ui/codicons/codicon/codicon.ttf").read_bytes() == ttf_before
    assert (vendor / "monaco/vs/editor/editor.main.css").read_text() == css_before


def test_missing_pattern_raises_systemexit(tmp_path):
    vendor = tmp_path / "vendor"
    css_dir = vendor / "monaco/vs/editor"
    css_dir.mkdir(parents=True)
    # A data:font/ttf that is NOT the codicon @font-face — the codemod must
    # fail rather than silently skip (a version bump could drop the font).
    (css_dir / "editor.main.css").write_text(
        "@font-face{font-family:other;src:url(data:font/ttf;base64,AAAA)}"
    )

    result = run_codemod(vendor)
    assert result.returncode != 0
    assert "codicon @font-face with data:font/ttf not found" in result.stderr


def test_build_sh_wires_codemod_after_csp_worker_patch():
    src = BUILD_SH.read_text()
    csp = 'python3 "${SCRIPT_DIR}/src/patch-csp-worker.py" "${WORK}"'
    font = 'python3 "${SCRIPT_DIR}/src/extract-codicon-font.py" "${WORK}"'
    assert csp in src
    assert font in src
    assert src.index(font) > src.index(csp)