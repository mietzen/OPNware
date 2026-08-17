/*!
 * monaco-editor-textmate.js — OPNware shared Monaco<->TextMate bridge.
 *
 * Registers a vscode-textmate grammar as a Monaco language token provider.
 * This is a drop-in for the npm `monaco-editor-textmate` package, adapted to
 * the modern `vscode-textmate` + `vscode-oniguruma` stack (the npm package
 * itself pins the abandoned `monaco-textmate`/`onigasm` chain and cannot be
 * loaded from a plain browser page). See docs/design/shared-editor-vendor.md.
 *
 * API (mirrors the npm package):
 *   wireTmGrammars(monaco, registry, languages) -> Promise<void[]>
 *     monaco    — the monaco-editor namespace (the `monaco` global)
 *     registry  — a vscode-textmate `Registry` (onigLib wired)
 *     languages — Map<languageId, textmateScopeName>, e.g.
 *                 new Map([['caddyfile', 'source.Caddyfile']])
 *
 *   resolveTokenScope(scopes) -> string   (pure)
 *     scopes — the vscode-textmate scope stack for one token, most-general
 *              first (e.g. ["source.Caddyfile", "entity.name.function.Caddyfile"]).
 *     Returns the single dotted scope string Monaco's classic TokensProvider
 *     contract expects. Monaco's theme trie splits a token scope ONLY on '.'
 *     and walks existing trie nodes, so a space-joined scope stack never
 *     matches any trie path and every token falls back to the default mtk1.
 *     This walks the stack from most-specific to least-specific, trying each
 *     scope's progressively shorter dotted prefixes, and returns the first
 *     prefix that the theme trie would actually color (see COLORABLE_SCOPES).
 *     If nothing matches it falls back to the most-specific full scope string.
 *
 *   defineEditorThemes(monaco)
 *     Defines the extended editor themes (opnware-vs / opnware-vs-dark) via
 *     the PUBLIC monaco.editor.defineTheme API. The built-in vs / vs-dark /
 *     hc themes contain NO entity.* or support.* token rules, so Caddyfile
 *     directives (entity.name.function.Caddyfile) and matchers / global
 *     options (support.function / support.constant) would otherwise render
 *     with the default mtk1 color even with a correct dotted scope. These
 *     themes inherit the base and add rules on top so those scopes color.
 *     Idempotent: safe to call more than once.
 *
 *   EDITOR_THEMES — the pure theme data (base / inherit / rules) used by
 *     defineEditorThemes, exported so it can be asserted without monaco.
 *
 * Token scopes are emitted as a single dotted scope string (see
 * resolveTokenScope), so the theme's generic rules (comment / string /
 * keyword / number ...) color the grammar output with the built-in vs /
 * vs-dark / hc themes, and the extended opnware themes additionally color
 * entity.name.function / support.function / support.constant.
 */
(function (root, factory) {
    if (typeof define === 'function' && define.amd) {
        // Monaco AMD loader (vs/loader.js)
        define([], factory);
    } else if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.MonacoEditorTextmate = factory();
    }
}(this, function () {
    'use strict';

    var TokenizerState = function (ruleStack) {
        this._ruleStack = ruleStack;
    };
    TokenizerState.prototype.getRuleStack = function () {
        return this._ruleStack;
    };
    TokenizerState.prototype.clone = function () {
        return new TokenizerState(this._ruleStack);
    };
    TokenizerState.prototype.equals = function (other) {
        return !!(other && other instanceof TokenizerState && other === this);
    };

    /**
     * The set of dotted scope prefixes that a Monaco theme trie actually
     * colors. Monaco's theme trie needs a rule node at exactly the segment
     * path being matched; a token scope like `comment.line.Caddyfile` colors
     * because the trie walks comment -> line -> (Caddyfile missing, falls back
     * to the comment.line rule). So the colorable prefixes are the generic
     * prefixes every built-in theme defines, PLUS the extended ones the
     * bridge's own themes (defineEditorThemes) add.
     *
     * Because getTheme() is NOT part of Monaco's public standalone API, the
     * bridge cannot query the live theme — this constant encodes the known
     * colorable set instead.
     */
    var COLORABLE_SCOPES = {
        'comment': true,
        'string': true,
        'keyword': true,
        'number': true,
        'constant': true,
        'variable': true,
        'regexp': true,
        'regex': true,
        'type': true,
        'delimiter': true,
        'tag': true,
        'meta': true,
        'metatag': true,
        'key': true,
        'attribute.name': true,
        'attribute.value': true,
        'operator': true,
        'predefined': true,
        'invalid': true,
        'annotation': true,
        'emphasis': true,
        'strong': true,
        // Extended by defineEditorThemes (opnware-vs / opnware-vs-dark).
        'entity.name.function': true,
        'support.function': true,
        'support.constant': true,
        'punctuation': true
    };

    /**
     * Pure: map a vscode-textmate scope stack to the single dotted scope
     * string Monaco's classic TokensProvider contract expects. See the header
     * docblock for the algorithm.
     */
    function resolveTokenScope(scopes) {
        if (!scopes || !scopes.length) {
            return '';
        }
        // Walk from most-specific to least-specific (scopes is most-general
        // first, so iterate in reverse).
        for (var i = scopes.length - 1; i >= 0; i--) {
            var scope = scopes[i];
            if (!scope) {
                continue;
            }
            var parts = scope.split('.');
            // Try progressively shorter dotted prefixes of this scope.
            for (var j = parts.length; j >= 1; j--) {
                var candidate = parts.slice(0, j).join('.');
                if (COLORABLE_SCOPES[candidate]) {
                    return candidate;
                }
            }
        }
        // Nothing matched a colorable prefix — fall back to the most-specific
        // full scope string.
        return scopes[scopes.length - 1];
    }

    /**
     * Pure theme data for the extended editor themes. Exported so tests can
     * assert it without a monaco instance.
     */
    var EDITOR_THEMES = {
        'opnware-vs': {
            base: 'vs',
            inherit: true,
            // colors must be an object — the standalone theme service reads
            // themeData.colors["editor.foreground"] directly when building the
            // token theme, and an undefined colors crashes editor.create.
            colors: {},
            rules: [
                { token: 'entity.name.function', foreground: '#795E26' },
                { token: 'support.function', foreground: '#795E26' },
                { token: 'support.constant', foreground: '#007998' }
            ]
        },
        'opnware-vs-dark': {
            base: 'vs-dark',
            inherit: true,
            colors: {},
            rules: [
                { token: 'entity.name.function', foreground: '#DCDCAA' },
                { token: 'support.function', foreground: '#DCDCAA' },
                { token: 'support.constant', foreground: '#4FC1FF' }
            ]
        }
    };

    var themesDefined = false;

    /**
     * Define the extended editor themes via the PUBLIC monaco.editor.defineTheme
     * API. Idempotent — safe to call more than once (guarded by a module-level
     * flag, since querying the live theme is not part of the public API).
     */
    function defineEditorThemes(monaco) {
        if (themesDefined) {
            return;
        }
        themesDefined = true;
        var names = Object.keys(EDITOR_THEMES);
        for (var i = 0; i < names.length; i++) {
            var name = names[i];
            var data = EDITOR_THEMES[name];
            monaco.editor.defineTheme(name, {
                base: data.base,
                inherit: data.inherit,
                colors: data.colors,
                rules: data.rules
            });
        }
    }

    /**
     * Wire each language in `languages` to its TextMate grammar.
     * `null` is a valid vscode-textmate initial rule stack.
     */
    function wireTmGrammars(monaco, registry, languages) {
        return Promise.all(Array.from(languages.keys()).map(function (languageId) {
            return registry.loadGrammar(languages.get(languageId)).then(function (grammar) {
                monaco.languages.setTokensProvider(languageId, {
                    getInitialState: function () {
                        return new TokenizerState(null);
                    },
                    tokenize: function (line, state) {
                        var res = grammar.tokenizeLine(line, state.getRuleStack());
                        var tokens = [];
                        for (var i = 0; i < res.tokens.length; i++) {
                            tokens.push({
                                startIndex: res.tokens[i].startIndex,
                                scopes: resolveTokenScope(res.tokens[i].scopes)
                            });
                        }
                        return {
                            endState: new TokenizerState(res.ruleStack),
                            tokens: tokens
                        };
                    }
                });
            });
        }));
    }

    return {
        wireTmGrammars: wireTmGrammars,
        resolveTokenScope: resolveTokenScope,
        defineEditorThemes: defineEditorThemes,
        EDITOR_THEMES: EDITOR_THEMES
    };
}));
