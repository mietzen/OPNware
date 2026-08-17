"""Source-seam + behavioral tests for the Monaco<->TextMate bridge (ticket: Caddyfile highlighting).

The bridge (pkgs/monaco-editor/src/monaco-editor-textmate.js) is the seam for
two bugs found on hardware:

1. It emitted each token's scope stack as a space-joined string
   (`scopes.join(' ')`). Monaco's classic TokensProvider contract expects ONE
   dotted scope string; its theme trie splits only on '.' and walks existing
   trie nodes, so a space-joined stack never matches any trie path and every
   token fell back to the default mtk1 color.
2. All four built-in Monaco themes contain NO entity.* / support.* token
   rules, so Caddyfile directives (entity.name.function.Caddyfile) and
   matchers / global options (support.function / support.constant) render
   mtk1 even with a correct dotted scope — unless the theme is extended.

The bridge fixes both: resolveTokenScope maps a scope stack to the single
dotted scope string the trie colors, and defineEditorThemes registers
extended themes (opnware-vs / opnware-vs-dark) that add entity/support rules
on top of the inherited base. The editor.volt wires the themes in before
monaco.editor.create and uses the opnware theme names.

The bridge is UMD (AMD + CommonJS + global), so the behavioral tests load it
via node's CommonJS branch and call resolveTokenScope / inspect EDITOR_THEMES
directly. If node is absent the source-seam tests still cover the invariants.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

BRIDGE = Path("pkgs/monaco-editor/src/monaco-editor-textmate.js")
EDITOR_VOLT = Path(
    "pkgs/os-caddy-advanced/src/opnsense/mvc/app/views/OPNsense/CaddyAdvanced/editor.volt"
)

NODE = shutil.which("node")


def run_node(js: str) -> str:
    """Run a JS snippet that requires the bridge by absolute path."""
    script = f"const b = require({str(BRIDGE.resolve())!r});\n{js}"
    result = subprocess.run(
        [NODE, "-e", script],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


# --- Source-seam tests -----------------------------------------------------


def test_bridge_no_longer_joins_scopes_with_space():
    src = BRIDGE.read_text()
    assert ".scopes.join(' ')" not in src
    assert ".scopes.join(" not in src


def test_bridge_exports_resolve_and_themes():
    src = BRIDGE.read_text()
    assert "function resolveTokenScope" in src
    assert "function defineEditorThemes" in src
    assert "resolveTokenScope: resolveTokenScope" in src
    assert "defineEditorThemes: defineEditorThemes" in src
    assert "EDITOR_THEMES: EDITOR_THEMES" in src


def test_bridge_uses_public_define_theme_api_only():
    src = BRIDGE.read_text()
    # No private internals: the bridge must not reach into monaco's theme
    # service or query the live theme (getTheme is not public standalone API).
    assert "monaco.editor.defineTheme" in src
    assert "_themeService" not in src
    assert "getColorTheme" not in src
    assert "monaco.editor.getTheme" not in src


def test_bridge_guards_define_themes_against_double_invocation():
    src = BRIDGE.read_text()
    assert "themesDefined" in src


def test_bridge_registration_passes_colors():
    # The defineTheme call inside defineEditorThemes MUST forward the colors
    # field from EDITOR_THEMES. The standalone theme service reads
    # themeData.colors["editor.foreground"] when building the token theme, and
    # dropping colors makes editor.create crash on any custom theme (found via
    # e2e on the VM: built-in themes create fine, custom themes throw
    # "Cannot read properties of undefined (reading 'editor.foreground')").
    src = BRIDGE.read_text()
    assert "base: data.base," in src
    assert "inherit: data.inherit," in src
    assert "colors: data.colors," in src
    assert "rules: data.rules" in src


def test_volt_defines_themes_before_create():
    src = EDITOR_VOLT.read_text()
    # The bridge must be loaded and defineEditorThemes called before the
    # editor is created with the opnware theme name.
    create_idx = src.index("monaco.editor.create")
    define_idx = src.index("bridge.defineEditorThemes(monaco)")
    assert define_idx < create_idx
    assert "monaco-editor-textmate" in src


def test_volt_uses_opnware_theme_names():
    src = EDITOR_VOLT.read_text()
    assert "opnware-vs-dark" in src
    assert "opnware-vs" in src
    # Selector options use the opnware names.
    assert '<option value="opnware-vs">' in src
    assert '<option value="opnware-vs-dark">' in src
    # Legacy stored values are mapped to the new names.
    assert "saved === 'vs'" in src
    assert "saved === 'vs-dark'" in src


# --- Behavioral tests (node) ----------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node not available")
def test_resolve_token_scope_behavior():
    cases = [
        # (scopes, expected)
        (["source.Caddyfile", "comment.line.Caddyfile"], "comment"),
        (["source.Caddyfile", "entity.name.function.Caddyfile"], "entity.name.function"),
        (["source.yaml", "string.quoted.double.yaml"], "string"),
        (["source.Caddyfile", "support.constant.Caddyfile"], "support.constant"),
        (["source.Caddyfile"], "source.Caddyfile"),  # fallback
    ]
    for scopes, expected in cases:
        js = f"console.log(JSON.stringify(b.resolveTokenScope({scopes!r})));"
        got = run_node(js)
        assert got == f'"{expected}"', f"resolveTokenScope({scopes!r}) -> {got}, want {expected!r}"


@pytest.mark.skipif(NODE is None, reason="node not available")
def test_resolve_token_scope_never_returns_space_joined():
    # The joined form must never be emitted: no space in any output.
    js = (
        "const out = [];\n"
        "out.push(b.resolveTokenScope(['source.Caddyfile', 'comment.line.Caddyfile']));\n"
        "out.push(b.resolveTokenScope(['source.Caddyfile', 'entity.name.function.Caddyfile']));\n"
        "out.push(b.resolveTokenScope(['source.Caddyfile', 'support.function.Caddyfile']));\n"
        "console.log(JSON.stringify(out));"
    )
    got = run_node(js)
    assert " " not in got


@pytest.mark.skipif(NODE is None, reason="node not available")
def test_editor_themes_data():
    # The theme data is a pure exported constant; assert base/inherit/rules
    # without a monaco instance.
    js = (
        "const names = Object.keys(b.EDITOR_THEMES).sort();\n"
        "console.log(JSON.stringify(names));\n"
        "for (const n of names) {\n"
        "  const t = b.EDITOR_THEMES[n];\n"
        "  console.log(n + '|' + t.base + '|' + t.inherit + '|' + (t.colors && typeof t.colors === 'object' ? 'colors-ok' : 'NO-COLORS') + '|' + JSON.stringify(t.rules));\n"
        "}"
    )
    out = run_node(js).splitlines()
    assert out[0] == '["opnware-vs","opnware-vs-dark"]'

    themes = {}
    for line in out[1:]:
        name, base, inherit, colors, rules_json = line.split("|", 4)
        themes[name] = {
            "base": base,
            "inherit": inherit,
            "colors": colors,
            "rules": __import__("json").loads(rules_json),
        }

    for name in ("opnware-vs", "opnware-vs-dark"):
        theme = themes[name]
        # The standalone theme service reads themeData.colors["editor.foreground"]
        # directly when building the token theme; a missing colors object
        # crashes editor.create (found via e2e on the VM).
        assert theme["colors"] == "colors-ok", f"{name}: colors must be an object"

    vs = themes["opnware-vs"]
    assert vs["base"] == "vs"
    assert vs["inherit"] == "true"  # JS boolean stringified
    vs_rules = {r["token"]: r["foreground"] for r in vs["rules"]}
    assert vs_rules["entity.name.function"] == "#795E26"
    assert vs_rules["support.function"] == "#795E26"
    assert vs_rules["support.constant"] == "#007998"

    dark = themes["opnware-vs-dark"]
    assert dark["base"] == "vs-dark"
    assert dark["inherit"] == "true"
    dark_rules = {r["token"]: r["foreground"] for r in dark["rules"]}
    assert dark_rules["entity.name.function"] == "#DCDCAA"
    assert dark_rules["support.function"] == "#DCDCAA"
    assert dark_rules["support.constant"] == "#4FC1FF"