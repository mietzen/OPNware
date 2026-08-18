/* OPNware shared Monaco editor — Caddyfile language (Monarch).
 *
 * Hand-written Monarch grammar that replaces the TextMate stack
 * (vscode-textmate + vscode-oniguruma + monaco-editor-textmate bridge +
 * caddyfile.tmLanguage.json). It is shipped by pkgs/monaco-editor/build.sh
 * as /ui/js/vendor/caddyfile.js and loaded by the editor pages through
 * Monaco's AMD loader as the 'caddyfile' module.
 *
 * Why Monarch instead of TextMate:
 *  - No TextMate runtime in the vendored Monaco build; the old setup shipped
 *    vscode-textmate + vscode-oniguruma + the oniguruma wasm, and the bridge
 *    had to map scope stacks to single dotted strings plus extend the stock
 *    themes with entity./support. rules (the stock vs/vs-dark themes have no
 *    such rules).
 *  - Monarch is built into Monaco: synchronous, no wasm, no extra runtime.
 *
 * Design decisions:
 *  - The grammar only emits tokens that exist in the stock vs/vs-dark themes
 *    (comment, keyword, string, number, type, variable, constant,
 *    delimiter.curly), so no theme extension is needed.
 *  - Heredocs embed a known language via nextEmbedded for the five
 *    well-known tags (CSS, HTML, JS|JAVASCRIPT, JSON, XML) and fall back to a
 *    generic heredoc state for any other tag.
 *  - All five embed targets are dedicated 'opnware-*' ids (opnware-css,
 *    opnware-html, opnware-js, opnware-json, opnware-xml) whose tokenizers
 *    are registered below via setMonarchTokensProvider. This is required: the
 *    built-in css/html/javascript/xml tokenizers in this standalone build are
 *    registered as LAZY factories (basic languages) or via
 *    onLanguage->setupMode (the rich css/html modes), and Monarch's embedded
 *    language path resolves TokenizationRegistry.get(id) SYNCHRONOUSLY while
 *    the model-tokenization path only ever resolves the model's own language.
 *    So get('css') returns null and the embed body degrades to plain text;
 *    direct synchronous registration (as with 'opnware-json') is the only way
 *    an embedded language resolves.
 *  - Monarch has NO backreferences, so the generic heredoc cannot match its
 *    terminator to the opening tag; it terminates on the first line that is a
 *    single bare word. This is a documented limitation.
 */
(function (root, factory) {
    if (typeof define === 'function' && define.amd) {
        define(['vs/editor/editor.main'], factory);
    } else if (typeof module === 'object' && module.exports) {
        module.exports = factory(null);
    } else {
        root.OPNwareCaddyfile = factory(root.monaco);
    }
}(typeof self !== 'undefined' ? self : this, function (monaco) {
    'use strict';

    var caddyfileConfig = {
        comments: {
            lineComment: '#'
        },
        brackets: [
            { open: '{', close: '}', token: 'delimiter.curly' }
        ],
        autoClosingPairs: [
            { open: '{', close: '}' },
            { open: '"', close: '"', notIn: ['string', 'comment'] },
            { open: '`', close: '`', notIn: ['string', 'comment'] }
        ]
    };

    var jsonConfig = {
        comments: {
            lineComment: '//'
        },
        brackets: [
            { open: '{', close: '}', token: 'delimiter.curly' },
            { open: '[', close: ']', token: 'delimiter.square' }
        ],
        autoClosingPairs: [
            { open: '{', close: '}' },
            { open: '[', close: ']' },
            { open: '"', close: '"', notIn: ['string'] }
        ]
    };

    /* The tokenizer mirrors the structure of the upstream Caddyfile TextMate
     * grammar (caddyserver/vscode-caddyfile): directives are keywords, the
     * domain/address left-hand side of a site block is 'type', matchers are
     * 'variable', and the content-type/status-code/placeholder rules cover the
     * argument positions. All emitted tokens exist in the stock vs/vs-dark
     * themes. */
    var caddyfileGrammar = {
        tokenizer: {
            // Shared by root and block (they add their own brace rules).
            body: [
                { include: '@comments' },
                { include: '@strings' },
                { include: '@heredoc' },
                { include: '@domains' },
                { include: '@statusCodes' },
                { include: '@paths' },
                { include: '@matchers' },
                { include: '@placeholders' },
                { include: '@contentTypes' },
                // First token of a line is a directive.
                [/^[ \t]*[a-zA-Z_\-+]+/, 'keyword'],
            ],
            root: [
                { include: '@body' },
                // A lone { at line start opens the global options block.
                [/^[ \t]*\{[ \t]*$/, 'delimiter.curly', '@global'],
                // Site block open.
                [/\{/, 'delimiter.curly', '@block'],
                // Anything else: plain text.
                [/[^\s]+/, '']
            ],
            block: [
                { include: '@body' },
                [/\{/, 'delimiter.curly', '@block'],
                [/\}/, 'delimiter.curly', '@pop'],
                [/[^\s]+/, '']
            ],
            global: [
                { include: '@comments' },
                // Global option names are 'constant' (support.constant in the
                // TextMate grammar, which the stock themes cannot color).
                [/^[ \t]*(?:debug|https?_port|default_bind|order|storage|storage_clean_interval|renew_interval|ocsp_interval|admin|log|grace_period|shutdown_delay|auto_https|email|default_sni|local_certs|skip_install_trust|acme_ca|acme_ca_root|acme_eab|acme_dns|on_demand_tls|key_type|cert_issuer|ocsp_stapling|preferred_chains|servers|pki|events)\b/, 'constant'],
                [/^[ \t]*\}[ \t]*$/, 'delimiter.curly', '@pop'],
                // Non-option line: swallow without styling.
                [/[ \t]*.*$/, '']
            ],
            comments: [
                [/^[ \t]*#.*$/, 'comment'],
                [/#.*$/, 'comment']
            ],
            strings: [
                [/"/, { token: 'string', next: '@stringDouble' }],
                [/`/, { token: 'string', next: '@stringBacktick' }]
            ],
            stringDouble: [
                [/[^"\\]+/, 'string'],
                [/\\./, 'constant'],
                [/"/, { token: 'string', next: '@pop' }]
            ],
            stringBacktick: [
                [/[^`]+/, 'string'],
                [/`/, { token: 'string', next: '@pop' }]
            ],
            heredoc: [
                [/[ \t]*<<\s*(?:CSS)[ \t]*$/, { token: 'string', next: '@heredocCSS', nextEmbedded: 'opnware-css' }],
                [/[ \t]*<<\s*(?:HTML)[ \t]*$/, { token: 'string', next: '@heredocHTML', nextEmbedded: 'opnware-html' }],
                [/[ \t]*<<\s*(?:JS|JAVASCRIPT)[ \t]*$/, { token: 'string', next: '@heredocJS', nextEmbedded: 'opnware-js' }],
                [/[ \t]*<<\s*(?:JSON)[ \t]*$/, { token: 'string', next: '@heredocJSON', nextEmbedded: 'opnware-json' }],
                [/[ \t]*<<\s*(?:XML)[ \t]*$/, { token: 'string', next: '@heredocXML', nextEmbedded: 'opnware-xml' }],
                // Any other tag: no embed (Monarch has no backreferences); the
                // terminator is the first line that is a single bare word.
                [/[ \t]*<<\s*[A-Za-z_][A-Za-z0-9_]*/, { token: 'string', next: '@heredocGeneric' }]
            ],
            // The five heredoc leave states are deliberately one-rule states:
            // each must match ONLY its own tag's terminator. Merging them
            // into one shared state with all five terminators would let a
            // body line equal to another tag (e.g. "HTML" inside a <<CSS
            // heredoc) end the embed prematurely. test_heredoc_embed_states_have_leave_rules
            // pins the one-leave-rule-per-embed-state invariant.
            heredocCSS: [
                [/^[ \t]*CSS[ \t]*$/, { token: 'string', next: '@pop', nextEmbedded: '@pop' }]
            ],
            heredocHTML: [
                [/^[ \t]*HTML[ \t]*$/, { token: 'string', next: '@pop', nextEmbedded: '@pop' }]
            ],
            heredocJS: [
                [/^[ \t]*(?:JS|JAVASCRIPT)[ \t]*$/, { token: 'string', next: '@pop', nextEmbedded: '@pop' }]
            ],
            heredocJSON: [
                [/^[ \t]*JSON[ \t]*$/, { token: 'string', next: '@pop', nextEmbedded: '@pop' }]
            ],
            heredocXML: [
                [/^[ \t]*XML[ \t]*$/, { token: 'string', next: '@pop', nextEmbedded: '@pop' }]
            ],
            heredocGeneric: [
                // No nextEmbedded here: this state is only reached when the
                // tag was not one of the five well-known ones.
                [/^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*$/, { token: 'string', next: '@pop' }],
                [/.*/, 'string']
            ],
            domains: [
                [/(?:https?:\/\/)*[a-z0-9-*]*(?:\.[a-zA-Z]{2,})+(?::[0-9]+)*\S*/, 'type'],
                [/localhost(?::[0-9]+)*/, 'type'],
                [/((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/, 'type'],
                [/(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))/, 'type'],
                [/:[0-9]+/, 'type']
            ],
            statusCodes: [
                [/[ \t][0-9]{3}(?!\.)/, 'number']
            ],
            paths: [
                [/(?:unix\/)*\/[a-zA-Z0-9_\-.\/*]+/, 'string'],
                [/\*\.[a-z]{1,5}/, 'variable'],
                [/\*\/?/, 'variable'],
                [/\?\//, 'variable']
            ],
            matchers: [
                [/@[^\s]+(?=\s)/, 'variable']
            ],
            placeholders: [
                [/[\{][\[\]\w.$+-]+[\}]/, 'variable']
            ],
            contentTypes: [
                [/(?:application|audio|example|font|image|message|model|multipart|text|video)\/[a-zA-Z0-9*+\-.]+;* *[a-zA-Z0-9=\-]*/, 'string']
            ]
        }
    };

    /* Small JSON tokenizer for <<JSON heredocs. JSON is not a basic Monaco
     * language (it needs the worker), so this registers a dedicated id. The
     * emitted tokens (string.key.json / string.value.json / keyword.json /
     * number / constant / delimiter.*) all exist in the stock themes. */
    var jsonGrammar = {
        tokenizer: {
            root: [
                [/[ \t\r\n]+/, ''],
                [/"([^"\\]|\\.)*"(?=\s*:)/, 'string.key.json'],
                [/"([^"\\]|\\.)*"/, 'string.value.json'],
                [/[{}]/, 'delimiter.curly'],
                [/[\[\]]/, 'delimiter.square'],
                [/[,:]/, 'delimiter'],
                [/\b(?:true|false)\b/, 'keyword.json'],
                [/\bnull\b/, 'constant'],
                [/[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/, 'number']
            ]
        }
    };

    /* The four tokenizers below are dedicated ids for <<CSS/<<HTML/<<JS/<<XML
     * heredocs. They must be registered HERE, synchronously, because the
     * built-in css/html/javascript/xml tokenizers are lazy in this build and
     * Monarch's embedded path only resolves synchronously-registered
     * languages (see the header comment). Each is a compact hand-written
     * Monarch grammar mirroring the constructs Monaco's own basic-language
     * tokenizers cover, and each only emits tokens that exist in the stock
     * vs/vs-dark themes. */

    var cssConfig = {
        comments: { blockComment: ['/*', '*/'] },
        brackets: [
            { open: '{', close: '}', token: 'delimiter.curly' },
            { open: '[', close: ']', token: 'delimiter.square' },
            { open: '(', close: ')', token: 'delimiter' }
        ],
        autoClosingPairs: [
            { open: '{', close: '}' },
            { open: '[', close: ']' },
            { open: '(', close: ')' },
            { open: '"', close: '"', notIn: ['string'] },
            { open: "'", close: "'", notIn: ['string'] }
        ]
    };

    /* Selectors are 'type', at-rules 'keyword', declaration property names
     * 'variable', values get number/string/constant, punctuation 'delimiter'. */
    var cssGrammar = {
        tokenizer: {
            root: [
                { include: '@comments' },
                { include: '@strings' },
                // at-rules (@media, @import, @keyframes, @font-face, ...)
                [/@[a-zA-Z][a-zA-Z0-9-]*/, 'keyword'],
                // class / id / pseudo selectors
                [/[.#%][a-zA-Z][a-zA-Z0-9_-]*/, 'type'],
                [/:{1,2}[a-zA-Z-]+/, 'type'],
                [/\[[^\]]*\]/, 'type'],
                [/[>+~,]/, 'delimiter'],
                [/\*/, 'type'],
                // declaration block open
                [/\{/, { token: 'delimiter.curly', next: '@rulebody' }],
                // element / bare-word selector
                [/[^\s{}]+/, 'type']
            ],
            rulebody: [
                { include: '@comments' },
                { include: '@strings' },
                { include: '@values' },
                // property name
                [/[a-zA-Z-]+(?=\s*:)/, 'variable'],
                [/:/, 'delimiter'],
                // nested declaration block (e.g. @keyframes)
                [/\{/, { token: 'delimiter.curly', next: '@rulebody' }],
                [/\}/, { token: 'delimiter.curly', next: '@pop' }],
                [/;/, 'delimiter'],
                [/[^\s}]+/, '']
            ],
            values: [
                [/[+-]?(\d*\.)?\d+(?:[a-zA-Z%]+)?/, 'number'],
                [/#[0-9a-fA-F]{3,8}\b/, 'constant'],
                [/!important\b/, 'keyword'],
                [/url(?=\()/, 'constant']
            ],
            strings: [
                [/"/, { token: 'string', next: '@stringDouble' }],
                [/'/, { token: 'string', next: '@stringSingle' }]
            ],
            stringDouble: [
                [/[^"\\]+/, 'string'],
                [/\\./, 'constant'],
                [/"/, { token: 'string', next: '@pop' }]
            ],
            stringSingle: [
                [/[^'\\]+/, 'string'],
                [/\\./, 'constant'],
                [/'/, { token: 'string', next: '@pop' }]
            ],
            comments: [
                [/\/\*/, { token: 'comment', next: '@comment' }],
                [/\/\/.*$/, 'comment']
            ],
            comment: [
                [/\*\//, { token: 'comment', next: '@pop' }],
                [/[^*]+/, 'comment'],
                [/./, 'comment']
            ]
        }
    };

    var htmlConfig = {
        comments: { blockComment: ['<!--', '-->'] },
        brackets: [
            { open: '<', close: '>', token: 'delimiter' }
        ],
        autoClosingPairs: [
            { open: '<', close: '>' },
            { open: '"', close: '"' },
            { open: "'", close: "'" }
        ]
    };

    /* Tags are 'type' (script/style 'keyword'), attribute names 'type',
     * attribute values 'string', comments 'comment', text plain. */
    var htmlGrammar = {
        tokenizer: {
            root: [
                [/<!--/, { token: 'comment', next: '@comment' }],
                [/<!DOCTYPE[^>]*>/i, 'keyword'],
                [/(<)(script)(?=[\s>\/])/i, ['delimiter', { token: 'keyword', next: '@tag' }]],
                [/(<)(style)(?=[\s>\/])/i, ['delimiter', { token: 'keyword', next: '@tag' }]],
                // open/close tag: <name or </name
                [/(<\/?)([a-zA-Z][a-zA-Z0-9-]*)/, ['delimiter', { token: 'type', next: '@tag' }]],
                [/</, 'delimiter'],
                // text
                [/[^<]+/, '']
            ],
            tag: [
                { include: '@comments' },
                // attribute name (followed by =)
                [/[a-zA-Z][a-zA-Z0-9-]*(?=\s*=)/, 'type'],
                [/=/, 'delimiter'],
                [/"[^"]*"/, 'string'],
                [/'[^']*'/, 'string'],
                // bare attribute
                [/[a-zA-Z][a-zA-Z0-9-]*/, 'type'],
                // end of tag
                [/[\/>]/, { token: 'delimiter', next: '@pop' }],
                [/[ \t\r\n]+/, '']
            ],
            comment: [
                [/-->/, { token: 'comment', next: '@pop' }],
                [/[^-]+/, 'comment'],
                [/./, 'comment']
            ]
        }
    };

    var jsConfig = {
        comments: { lineComment: '//', blockComment: ['/*', '*/'] },
        brackets: [
            { open: '{', close: '}', token: 'delimiter.curly' },
            { open: '[', close: ']', token: 'delimiter.square' },
            { open: '(', close: ')', token: 'delimiter' }
        ],
        autoClosingPairs: [
            { open: '{', close: '}' },
            { open: '[', close: ']' },
            { open: '(', close: ')' },
            { open: '"', close: '"', notIn: ['string'] },
            { open: "'", close: "'", notIn: ['string', 'comment'] },
            { open: '`', close: '`', notIn: ['string', 'comment'] }
        ]
    };

    /* Keywords 'keyword', booleans/null 'constant', strings/numbers/comments
     * the stock tokens, operators and punctuation 'delimiter', capitalized
     * names 'type'. Mirrors the constructs of Monaco's TS/JS basic language. */
    var jsGrammar = {
        keywords: [
            'async', 'await', 'break', 'case', 'catch', 'class', 'const',
            'continue', 'debugger', 'default', 'delete', 'do', 'else',
            'export', 'extends', 'finally', 'for', 'from', 'function', 'get',
            'if', 'import', 'in', 'instanceof', 'let', 'new', 'of', 'return',
            'set', 'static', 'super', 'switch', 'this', 'throw', 'try',
            'typeof', 'var', 'void', 'while', 'with', 'yield'
        ],
        constants: ['true', 'false', 'null', 'undefined', 'NaN', 'Infinity'],
        tokenizer: {
            root: [
                { include: '@whitespace' },
                // identifiers and keywords (lowercase start, so capitalized
                // names fall through to the type rule below)
                [/[a-z_$][\w$]*/, {
                    cases: {
                        '@keywords': 'keyword',
                        '@constants': 'constant',
                        '@default': ''
                    }
                }],
                [/[A-Z][\w$]*/, 'type'],
                // numbers
                [/0[xX][0-9a-fA-F]+n?/, 'number'],
                [/0[bB][01]+n?/, 'number'],
                [/0[oO][0-7]+n?/, 'number'],
                [/\.?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/, 'number'],
                // strings
                [/"/, { token: 'string', next: '@stringDouble' }],
                [/'/, { token: 'string', next: '@stringSingle' }],
                [/`/, { token: 'string', next: '@stringBacktick' }],
                // delimiters and operators
                [/[()[\]]/, 'delimiter'],
                [/[{}]/, 'delimiter.curly'],
                [/[=<>!~?:&|+\-*/^%]+/, 'delimiter'],
                [/[;,.@]/, 'delimiter'],
                [/[^\s]+/, '']
            ],
            stringDouble: [
                [/[^"\\]+/, 'string'],
                [/\\./, 'constant'],
                [/"/, { token: 'string', next: '@pop' }]
            ],
            stringSingle: [
                [/[^'\\]+/, 'string'],
                [/\\./, 'constant'],
                [/'/, { token: 'string', next: '@pop' }]
            ],
            stringBacktick: [
                [/[^`\\]+/, 'string'],
                [/\\./, 'constant'],
                [/`/, { token: 'string', next: '@pop' }]
            ],
            whitespace: [
                [/[ \t\r\n]+/, ''],
                [/\/\*/, { token: 'comment', next: '@comment' }],
                [/\/\/.*$/, 'comment']
            ],
            comment: [
                [/\*\//, { token: 'comment', next: '@pop' }],
                [/[^*]+/, 'comment'],
                [/./, 'comment']
            ]
        }
    };

    var xmlConfig = {
        comments: { blockComment: ['<!--', '-->'] },
        brackets: [
            { open: '<', close: '>', token: 'delimiter' }
        ],
        autoClosingPairs: [
            { open: '<', close: '>' },
            { open: "'", close: "'" },
            { open: '"', close: '"' }
        ]
    };

    /* Tags are 'type', meta/declaration names 'keyword', attributes 'type',
     * attribute values / entities / CDATA 'string', comments 'comment'. */
    var xmlGrammar = {
        tokenizer: {
            root: [
                [/<!--/, { token: 'comment', next: '@comment' }],
                // processing instructions and declarations: <?name ... ?> / <!name ...>
                [/(<\?)([a-zA-Z_][a-zA-Z0-9_.:-]*)/, ['delimiter', { token: 'keyword', next: '@pi' }]],
                [/(<!)([a-zA-Z_][a-zA-Z0-9_.:-]*)/, ['delimiter', { token: 'keyword', next: '@pi' }]],
                // CDATA sections
                [/<!\[CDATA\[/, { token: 'string', next: '@cdata' }],
                // entities
                [/&[a-zA-Z0-9#]+;/, 'string'],
                // closing tag
                [/(<\/)([a-zA-Z_][a-zA-Z0-9_.:-]*)/, ['delimiter', { token: 'type', next: '@closeTag' }]],
                // opening tag
                [/(<)([a-zA-Z_][a-zA-Z0-9_.:-]*)/, ['delimiter', { token: 'type', next: '@openTag' }]],
                [/</, 'delimiter'],
                // text
                [/[^<&]+/, '']
            ],
            openTag: [
                { include: '@attrs' },
                [/\/?>/, { token: 'delimiter', next: '@pop' }],
                [/[^\s>]+/, '']
            ],
            closeTag: [
                [/>/, { token: 'delimiter', next: '@pop' }],
                [/[^>]+/, '']
            ],
            pi: [
                [/"/, { token: 'string', next: '@piStringDouble' }],
                [/'/, { token: 'string', next: '@piStringSingle' }],
                [/\?>/, { token: 'delimiter', next: '@pop' }],
                [/>/, { token: 'delimiter', next: '@pop' }],
                [/[^\s>]+/, 'constant'],
                [/[ \t\r\n]+/, '']
            ],
            attrs: [
                [/[ \t\r\n]+/, ''],
                [/[a-zA-Z_][a-zA-Z0-9_.:-]*(?=\s*=)/, 'type'],
                [/=/, 'delimiter'],
                [/"[^"]*"/, 'string'],
                [/'[^']*'/, 'string'],
                [/[a-zA-Z_][a-zA-Z0-9_.:-]*/, 'type']
            ],
            piStringDouble: [
                [/[^"]+/, 'string'],
                [/"/, { token: 'string', next: '@pop' }]
            ],
            piStringSingle: [
                [/[^']+/, 'string'],
                [/'/, { token: 'string', next: '@pop' }]
            ],
            cdata: [
                [/\]\]>/, { token: 'string', next: '@pop' }],
                [/[^\]]+/, 'string'],
                [/\]/, 'string']
            ],
            comment: [
                [/-->/, { token: 'comment', next: '@pop' }],
                [/[^-]+/, 'comment'],
                [/./, 'comment']
            ]
        }
    };

    if (monaco) {
        monaco.languages.register({ id: 'caddyfile' });
        monaco.languages.setLanguageConfiguration('caddyfile', caddyfileConfig);
        monaco.languages.setMonarchTokensProvider('caddyfile', caddyfileGrammar);

        monaco.languages.register({ id: 'opnware-json' });
        monaco.languages.setLanguageConfiguration('opnware-json', jsonConfig);
        monaco.languages.setMonarchTokensProvider('opnware-json', jsonGrammar);

        monaco.languages.register({ id: 'opnware-css' });
        monaco.languages.setLanguageConfiguration('opnware-css', cssConfig);
        monaco.languages.setMonarchTokensProvider('opnware-css', cssGrammar);

        monaco.languages.register({ id: 'opnware-html' });
        monaco.languages.setLanguageConfiguration('opnware-html', htmlConfig);
        monaco.languages.setMonarchTokensProvider('opnware-html', htmlGrammar);

        monaco.languages.register({ id: 'opnware-js' });
        monaco.languages.setLanguageConfiguration('opnware-js', jsConfig);
        monaco.languages.setMonarchTokensProvider('opnware-js', jsGrammar);

        monaco.languages.register({ id: 'opnware-xml' });
        monaco.languages.setLanguageConfiguration('opnware-xml', xmlConfig);
        monaco.languages.setMonarchTokensProvider('opnware-xml', xmlGrammar);
    }

    return {
        caddyfileGrammar: caddyfileGrammar,
        caddyfileConfig: caddyfileConfig,
        jsonGrammar: jsonGrammar,
        jsonConfig: jsonConfig,
        cssGrammar: cssGrammar,
        cssConfig: cssConfig,
        htmlGrammar: htmlGrammar,
        htmlConfig: htmlConfig,
        jsGrammar: jsGrammar,
        jsConfig: jsConfig,
        xmlGrammar: xmlGrammar,
        xmlConfig: xmlConfig
    };
}));
