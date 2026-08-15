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
 * Token scopes are emitted as a space-joined scope stack, so the monaco
 * theme's generic rules (comment / string / keyword / number ...) color the
 * grammar output with the built-in vs / vs-dark / hc themes.
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
                                scopes: res.tokens[i].scopes.join(' ')
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
        wireTmGrammars: wireTmGrammars
    };
}));
