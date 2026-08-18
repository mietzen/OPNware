"""Source-seam + structural tests for the Caddyfile Monarch grammar (ticket: Caddyfile highlighting).

The grammar (pkgs/monaco-editor/src/caddyfile.js) is a hand-written Monarch
tokenizer that replaces the TextMate stack — vscode-textmate,
vscode-oniguruma, the hand-rolled bridge (monaco-editor-textmate.js) and the
TextMate grammar JSON. It registers six languages via the public
monaco.languages API ('caddyfile', plus the dedicated 'opnware-json' /
'opnware-css' / 'opnware-html' / 'opnware-js' / 'opnware-xml' tokenizers used
by the heredoc embeds) and is shipped as /ui/js/vendor/caddyfile.js.

Why the invariants in this file matter (all found on hardware in the TextMate
era):

1. The old bridge emitted each token's scope stack as a space-joined string.
   Monaco's classic TokensProvider contract expects ONE dotted scope string;
   its theme trie splits only on '.' and walks existing trie nodes, so a
   space-joined stack never matched and every token fell back to the default
   mtk1 color.
2. All four built-in Monaco themes contain NO entity.* / support.* token
   rules, so the TextMate grammar's Caddyfile scopes rendered mtk1 unless the
   bridge registered extended themes. The Monarch grammar therefore only
   emits tokens that exist in the stock vs/vs-dark themes — this file pins
   that by extracting the token names used in the grammar and comparing them
   against the stock-theme token set.
3. A Monarch embedded language (nextEmbedded) without a leave rule that pops
   it throws "no rule containing nextEmbedded: @pop in tokenizer embedded
   state" — every heredoc embed state must have one. The heredoc leave
   states are deliberately one-rule per tag (a merged state with all five
   terminators would let a body line equal to another tag end the embed
   early).
4. nextEmbedded targets must be languages that are actually registered in
   this Monaco build — and synchronously. The built-in
   css/html/javascript/xml tokenizers are lazy factories in the standalone
   build and Monarch's embedded path resolves TokenizationRegistry.get(id)
   synchronously while the model path only resolves the model's own language,
   so embedding them renders plain text. The grammar therefore registers its
   own 'opnware-*' tokenizers directly via setMonarchTokensProvider.

The "brittle-looking" pins in this file (the full state-set assertion and
the "fetch(" exclusion) are deliberate contracts, not accidents: the state
set is the grammar's public shape and any structural change must be a
conscious act (update the pin in the same commit); the grammar must stay
synchronous (no fetch) so the editor pages need no async wiring. Node's
returncode is checked in load_grammar so a broken grammar fails loudly
instead of silently producing empty tokens.

The grammar file is UMD; when node is present the structural tests load it
via the CommonJS branch (factory(null)) and inspect the exported tokenizers.
Without node, the source-seam tests still cover the file/volt/build.sh
invariants.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

GRAMMAR = Path("pkgs/monaco-editor/src/caddyfile.js")
EDITOR_VOLT = Path(
    "pkgs/os-caddy-advanced/src/opnsense/mvc/app/views/OPNsense/CaddyAdvanced/editor.volt"
)
EDITOR_CONTROLLER = Path(
    "pkgs/os-caddy-advanced/src/opnsense/mvc/app/controllers/OPNsense/CaddyAdvanced/EditorController.php"
)
HOMER_CONFIG_CONTROLLER = Path(
    "pkgs/os-homer/src/opnsense/mvc/app/controllers/OPNsense/Homer/ConfigController.php"
)
BUILD_SH = Path("pkgs/monaco-editor/build.sh")

NODE = shutil.which("node")

# Tokens that exist in the stock vs/vs-dark themes of a default Monaco build.
# The Monarch grammar must only use these so no theme extension is needed.
STOCK_THEME_TOKENS = {
    "",  # no token (plain text)
    "comment",
    "constant",
    "delimiter",
    "delimiter.curly",
    "delimiter.square",
    "keyword",
    "keyword.json",
    "number",
    "string",
    "string.key.json",
    "string.value.json",
    "type",
    "variable",
}

# Languages that the heredoc embeds may target. These are the dedicated
# tokenizers the grammar registers itself (the built-in css/html/javascript/
# xml tokenizers are lazy in the standalone build and cannot resolve through
# Monarch's synchronous embedded path).
EMBEDDABLE_LANGUAGES = {"opnware-css", "opnware-html", "opnware-js", "opnware-json", "opnware-xml"}


def load_grammar():
    """Load caddyfile.js via node's CommonJS branch and return the exports."""
    script = (
        f"const mod = require({str(GRAMMAR.resolve())!r});\n"
        "console.log(JSON.stringify(mod));"
    )
    result = subprocess.run(
        [NODE, "-e", script],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return __import__("json").loads(result.stdout)


def walk_tokenizer(tokenizer):
    """Walk every state of a Monarch tokenizer.

    Returns (states, nexts, embeds, leave_states, embed_states):
      states      - set of state names (keys)
      nexts       - set of next: targets (without the leading @)
      embeds      - set of nextEmbedded: values
      leave_states- states containing a rule with nextEmbedded '@pop'
      embed_states- states entered via a rule with a real nextEmbedded
    """
    states = set(tokenizer.keys())
    nexts, embeds = set(), set()
    leave_states, embed_states = set(), set()
    for state, rules in tokenizer.items():
        for rule in rules:
            action = rule[1] if isinstance(rule, (list, tuple)) and len(rule) >= 2 else None
            if isinstance(action, dict):
                if action.get("next"):
                    nexts.add(action["next"].lstrip("@"))
                if action.get("nextEmbedded"):
                    embeds.add(action["nextEmbedded"])
                    if action["nextEmbedded"] == "@pop":
                        leave_states.add(state)
                    else:
                        embed_states.add(action.get("next", "").lstrip("@"))
    return states, nexts, embeds, leave_states, embed_states


def emitted_tokens(tokenizer):
    """Every token name the tokenizer emits (string actions, dict tokens,
    'cases' mappings, and group/array actions)."""
    tokens = set()

    def collect(action):
        if isinstance(action, str):
            tokens.add(action)
        elif isinstance(action, dict):
            if action.get("token"):
                tokens.add(action["token"])
            for case_token in (action.get("cases") or {}).values():
                if isinstance(case_token, str):
                    tokens.add(case_token)
        elif isinstance(action, (list, tuple)):
            for sub in action:
                collect(sub)

    for rules in tokenizer.values():
        for rule in rules:
            if isinstance(rule, (list, tuple)) and len(rule) >= 2:
                collect(rule[1])
    return tokens


# --- Source-seam tests -----------------------------------------------------


def test_grammar_usages_public_monaco_languages_api():
    src = GRAMMAR.read_text()
    assert "monaco.languages.register" in src
    assert "monaco.languages.setLanguageConfiguration" in src
    assert "monaco.languages.setMonarchTokensProvider" in src
    # Registers exactly the six languages (caddyfile + the five opnware-*
    # heredoc embed tokenizers).
    assert "id: 'caddyfile'" in src
    for lang_id in ("opnware-json", "opnware-css", "opnware-html", "opnware-js", "opnware-xml"):
        assert f"id: '{lang_id}'" in src


def test_grammar_is_umd():
    src = GRAMMAR.read_text()
    assert "define.amd" in src
    assert "module.exports" in src
    assert "monaco.languages.register" in src


def test_grammar_has_no_stale_textmate_dependencies():
    src = GRAMMAR.read_text()
    # The header comment names the TextMate stack components it replaces, so
    # component names as words are fine; the grammar must not contain any of
    # the removed stack's functional identifiers.
    assert "loadWASM" not in src
    assert "wireTmGrammars" not in src
    assert "tm.Registry" not in src
    assert "createOnigScanner" not in src
    assert "fetch(" not in src  # Monarch tokenizes synchronously, no fetches


def test_volt_uses_caddyfile_module_not_textmate():
    src = EDITOR_VOLT.read_text()
    assert "caddyfile: '/ui/js/vendor/caddyfile'" in src
    assert "'caddyfile']" in src  # the grammar is a required AMD dependency
    assert "monaco-editor-textmate" not in src
    assert "vscode-textmate" not in src
    assert "onig" not in src
    assert "tmLanguage" not in src


def test_volt_uses_stock_theme_names():
    src = EDITOR_VOLT.read_text()
    # The selector options use the stock theme names.
    assert '<option value="vs">' in src
    assert '<option value="vs-dark">' in src
    # No extended-theme wiring remains.
    assert "defineEditorThemes" not in src
    assert "theme: 'opnware-vs'" not in src
    # Legacy stored values (the bridge-era extended theme names) are mapped
    # back to the stock names — the only place the old names remain.
    assert "saved === 'opnware-vs'" in src
    assert "saved === 'opnware-vs-dark'" in src


def test_build_sh_drops_textmate_stack():
    src = BUILD_SH.read_text()
    assert "TEXTMATE_VERSION" not in src
    assert "ONIGURUMA_VERSION" not in src
    assert "vscode-textmate" not in src
    assert "vscode-oniguruma" not in src
    assert "onig.wasm" not in src
    assert "monaco-editor-textmate" not in src
    assert "tmLanguage" not in src
    # The grammar is copied into the vendored tree.
    assert "src/caddyfile.js" in src
    assert "${WORK}/caddyfile.js" in src


def test_old_textmate_artifacts_are_gone():
    assert not Path("pkgs/monaco-editor/src/monaco-editor-textmate.js").exists()
    assert not Path("pkgs/monaco-editor/src/caddyfile.tmLanguage.json").exists()


def test_editor_controllers_declare_csp_extensions():
    # The deleted build-time codemods used to self-verify the CSP patch
    # ("fails the build if the pristine patterns change"); the replacement
    # per-controller CSP extension has no such gate, so this test pins it.
    # Both editor pages must extend OPNsense's default CSP with blob: workers
    # and data: fonts (Monaco's native blob workers + inline codicon font).
    # Keep in sync with docs/design/shared-editor-vendor.md.
    for controller in (EDITOR_CONTROLLER, HOMER_CONFIG_CONTROLLER):
        src = controller.read_text()
        assert "content_security_policy" in src, controller
        assert '"worker-src" => "\'self\' blob:"' in src, controller
        assert '"font-src" => "\'self\' data:"' in src, controller


# --- Structural tests (node) -----------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node not available")
def test_tokens_are_stock_theme_tokens_only():
    data = load_grammar()
    for name in ("caddyfileGrammar", "jsonGrammar", "cssGrammar", "htmlGrammar", "jsGrammar", "xmlGrammar"):
        tokens = emitted_tokens(data[name]["tokenizer"])
        unknown = tokens - STOCK_THEME_TOKENS
        assert not unknown, f"{name} emits tokens not in the stock themes: {sorted(unknown)}"


@pytest.mark.skipif(NODE is None, reason="node not available")
def test_heredoc_embed_states_have_leave_rules():
    data = load_grammar()
    tokenizer = data["caddyfileGrammar"]["tokenizer"]
    states, nexts, embeds, leave_states, embed_states = walk_tokenizer(tokenizer)
    # Every state entered with a real nextEmbedded must contain a leave rule
    # that pops the embed (Monarch throws otherwise).
    assert embed_states, "no heredoc embed states found"
    missing = embed_states - leave_states
    assert not missing, f"embed states without a nextEmbedded @pop leave rule: {sorted(missing)}"


@pytest.mark.skipif(NODE is None, reason="node not available")
def test_next_embedded_languages_are_registered():
    data = load_grammar()
    tokenizer = data["caddyfileGrammar"]["tokenizer"]
    _, _, embeds, _, _ = walk_tokenizer(tokenizer)
    real = {e for e in embeds if e != "@pop"}
    assert real <= EMBEDDABLE_LANGUAGES, f"unknown embed target: {sorted(real - EMBEDDABLE_LANGUAGES)}"


@pytest.mark.skipif(NODE is None, reason="node not available")
def test_next_targets_are_existing_states():
    data = load_grammar()
    for name in ("caddyfileGrammar", "jsonGrammar", "cssGrammar", "htmlGrammar", "jsGrammar", "xmlGrammar"):
        tokenizer = data[name]["tokenizer"]
        states, nexts, _, _, _ = walk_tokenizer(tokenizer)
        # @pop/@push/@pushall are built-in Monarch pseudo-states, not tokenizer states.
        unknown = nexts - states - {"pop", "push", "pushall"}
        assert not unknown, f"{name}: next targets without a state: {sorted(unknown)}"
    # Cross-language reaches (if any) go through nextEmbedded, which
    # test_next_embedded_languages_are_registered already pins.


@pytest.mark.skipif(NODE is None, reason="node not available")
def test_grammar_has_expected_structure():
    data = load_grammar()
    tokenizer = data["caddyfileGrammar"]["tokenizer"]
    states = set(tokenizer.keys())
    expected = {
        "root", "block", "global", "comments", "strings",
        "stringDouble", "stringBacktick",
        "heredoc", "heredocCSS", "heredocHTML", "heredocJS",
        "heredocJSON", "heredocXML", "heredocGeneric",
        "domains", "statusCodes", "paths", "matchers",
        "placeholders", "contentTypes",
    }
    assert expected <= states, sorted(expected - states)
    # JSON tokenizer is small and standalone.
    json_tokenizer = data["jsonGrammar"]["tokenizer"]
    assert set(json_tokenizer.keys()) == {"root"}
    # The four heredoc embed tokenizers each have a root state.
    for name in ("cssGrammar", "htmlGrammar", "jsGrammar", "xmlGrammar"):
        new_tokenizer = data[name]["tokenizer"]
        assert "root" in new_tokenizer, f"{name} is missing a root state"
        assert new_tokenizer["root"], f"{name} root state is empty"