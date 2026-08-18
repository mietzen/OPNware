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
 *  - JSON is NOT a basic language in this Monaco build (it is a rich
 *    worker-based language), so <<JSON heredocs embed 'opnware-json' — a
 *    small Monarch JSON tokenizer registered below.
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
            root: [
                { include: '@comments' },
                { include: '@strings' },
                { include: '@heredoc' },
                { include: '@domains' },
                { include: '@statusCodes' },
                { include: '@paths' },
                { include: '@matchers' },
                { include: '@placeholders' },
                { include: '@contentTypes' },
                // A lone { at line start opens the global options block.
                [/^[ \t]*\{[ \t]*$/, 'delimiter.curly', '@global'],
                // First token of a line is a directive.
                [/^[ \t]*[a-zA-Z_\-+]+/, 'keyword'],
                // Site block open.
                [/\{/, 'delimiter.curly', '@block'],
                // Anything else: plain text.
                [/[^\s]+/, '']
            ],
            block: [
                { include: '@comments' },
                { include: '@strings' },
                { include: '@heredoc' },
                { include: '@domains' },
                { include: '@statusCodes' },
                { include: '@paths' },
                { include: '@matchers' },
                { include: '@placeholders' },
                { include: '@contentTypes' },
                [/^[ \t]*[a-zA-Z_\-+]+/, 'keyword'],
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
                [/[ \t]*<<\s*(?:CSS)[ \t]*$/, { token: 'string', next: '@heredocCSS', nextEmbedded: 'css' }],
                [/[ \t]*<<\s*(?:HTML)[ \t]*$/, { token: 'string', next: '@heredocHTML', nextEmbedded: 'html' }],
                [/[ \t]*<<\s*(?:JS|JAVASCRIPT)[ \t]*$/, { token: 'string', next: '@heredocJS', nextEmbedded: 'javascript' }],
                [/[ \t]*<<\s*(?:JSON)[ \t]*$/, { token: 'string', next: '@heredocJSON', nextEmbedded: 'opnware-json' }],
                [/[ \t]*<<\s*(?:XML)[ \t]*$/, { token: 'string', next: '@heredocXML', nextEmbedded: 'xml' }],
                // Any other tag: no embed (Monarch has no backreferences); the
                // terminator is the first line that is a single bare word.
                [/[ \t]*<<\s*[A-Za-z_][A-Za-z0-9_]*/, { token: 'string', next: '@heredocGeneric' }]
            ],
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

    if (monaco) {
        monaco.languages.register({ id: 'caddyfile' });
        monaco.languages.setLanguageConfiguration('caddyfile', caddyfileConfig);
        monaco.languages.setMonarchTokensProvider('caddyfile', caddyfileGrammar);

        monaco.languages.register({ id: 'opnware-json' });
        monaco.languages.setLanguageConfiguration('opnware-json', jsonConfig);
        monaco.languages.setMonarchTokensProvider('opnware-json', jsonGrammar);
    }

    return {
        caddyfileGrammar: caddyfileGrammar,
        caddyfileConfig: caddyfileConfig,
        jsonGrammar: jsonGrammar,
        jsonConfig: jsonConfig
    };
}));
