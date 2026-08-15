# Shared vendored editor asset: Monaco + TextMate (os-caddy and os-homer)

The OPNsense web UI pages in this repo render a real code editor by shipping a
**shared, vendored** copy of the Monaco editor plus the TextMate grammar
support that gives the Caddyfile (and, for os-homer, YAML) its syntax
highlighting. Nothing is loaded from a CDN — every byte is installed with the
plugin package and served from the WebUI origin.

This document is the reference for how a plugin consumes the asset. Both the
os-caddy Caddyfile editor and the os-homer YAML config editor follow it.

## What is vendored and where

Source of truth: **`pkgs/editor/assets/vendor/`** (the single checked-in copy
of the asset in this repo — the `editor` package owns it).

```
assets/vendor/
├── monaco/
│   ├── package.json                       # monaco-editor provenance (drives the version)
│   └── vs/                                # monaco-editor standalone min build (the `min/vs` tree)
│       ├── loader.js                      # Monaco AMD loader (defines global require/define)
│       └── editor/editor.main.js (+ css, worker)
├── caddyfile.tmLanguage.json              # TextMate grammar, caddyserver/vscode-caddyfile (source.Caddyfile)
└── textmate/
    ├── vscode-textmate/                   # TextMate grammar engine (npm vscode-textmate)
    ├── vscode-oniguruma/release/          # oniguruma→wasm bindings + onig.wasm (npm vscode-oniguruma)
    └── monaco-editor-textmate.js          # hand-rolled bridge: TM grammar as a Monaco token provider
```

The `textmate/` files are the unpacked `release`/`dist` outputs of the npm
packages; `package.json`/license files are kept alongside for provenance.

> **Why a hand-rolled bridge instead of the npm `monaco-editor-textmate`
> package?** The npm package (4.x) pins the abandoned
> `monaco-textmate`/`onigasm` chain and cannot run in a plain browser page.
> `monaco-editor-textmate.js` implements the same
> `wireTmGrammars(monaco, registry, languages)` contract on top of the modern
> `vscode-textmate` + `vscode-oniguruma` stack (the stack VS Code itself uses
> today). Same API, current engine, no dead deps.

## How the vendor reaches the WebUI — the shared `editor` package

OPNsense serves `/opnsense/www/js/...` as the `/ui/js/...` URL prefix, so the
vendor tree must land under `/usr/local/opnsense/www/js/vendor/`. The files
are owned by the **`editor` package** (`pkgs/editor/`), a plain payload
package whose build.sh copies the checked-in `pkgs/editor/assets/vendor/`
tree into the payload:

```bash
# pkgs/editor/build.sh
cp -R "${SCRIPT_DIR}/assets/vendor/." \
      "${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js/vendor/"
```

Both plugins declare it as a pkg dependency (`deps: editor: opnware/editor`),
so `pkg` installs it first and no plugin payload ever owns the vendor files.
This is deliberate: shipping the same files in two plugin payloads would make
`pkg` refuse co-installation (duplicate file ownership). Never copy the
vendor into a plugin payload — change the `editor` package instead.

## How a volt page loads Monaco and registers a language

1. Load the Monaco AMD loader and point it at the vendored modules:

```html
<script src="/ui/js/vendor/monaco/vs/loader.js"></script>
<script>
    require.config({
        paths: {
            vs: '/ui/js/vendor/monaco/vs',
            'vscode-textmate': '/ui/js/vendor/textmate/vscode-textmate/main',
            'vscode-oniguruma': '/ui/js/vendor/textmate/vscode-oniguruma/release/main',
            'monaco-editor-textmate': '/ui/js/vendor/textmate/monaco-editor-textmate'
        }
    });
</script>
```

2. Create the editor, then wire the grammar. The grammar file is fetched from
   the WebUI origin (`/ui/js/vendor/caddyfile.tmLanguage.json`), and the
   oniguruma wasm is fetched as `ArrayBuffer` and passed to
   `onig.loadWASM({ data })` — both URLs are constructible from the same
   `/ui/js/vendor/...` base, so they always work once the payload is installed.

```js
require(['vs/editor/editor.main'], function (monaco) {
    monaco.languages.register({ id: 'caddyfile' });

    const editor = monaco.editor.create(document.getElementById('editor-container'), {
        value: '',
        language: 'caddyfile',
        theme: 'vs-dark',          // consistent with the OPNsense dark UI
        automaticLayout: true,
        minimap: { enabled: false },
        fontSize: 13,
        tabSize: 2,
        wordWrap: 'on'
    });

    require(['vscode-textmate', 'vscode-oniguruma', 'monaco-editor-textmate'],
        function (tm, onig, bridge) {
            fetch('/ui/js/vendor/textmate/vscode-oniguruma/release/onig.wasm')
                .then(r => r.arrayBuffer())
                .then(data => onig.loadWASM({ data }))
                .then(() => fetch('/ui/js/vendor/caddyfile.tmLanguage.json').then(r => r.json()))
                .then(grammarJson => {
                    const registry = new tm.Registry({
                        onigLib: Promise.resolve({
                            createOnigScanner: onig.createOnigScanner,
                            createOnigString: onig.createOnigString
                        }),
                        // vscode-textmate's loadGrammar returns the raw IRawGrammar object
                        // directly (NOT a { format, content } wrapper).
                        loadGrammar: scopeName =>
                            Promise.resolve(scopeName === 'source.Caddyfile' ? grammarJson : null)
                    });
                    return bridge.wireTmGrammars(
                        monaco, registry, new Map([['caddyfile', 'source.Caddyfile']])
                    );
                });
        });
});
```

Key points for a consumer:

- `loadGrammar` in the `vscode-textmate` `Registry` must resolve to the raw
  grammar object (`IRawGrammar`), keyed by its `scopeName` (`source.Caddyfile`
  here; `source.yaml` for os-homer).
- The grammar JSON and the wasm are fetched with absolute `/ui/...` URLs from
  the WebUI origin — never relative paths, never a CDN.
- Token scopes are emitted space-joined, so Monaco's built-in themes
  (`vs-dark` etc.) color the grammar output via their generic comment/string/
  keyword/number rules.

## Refreshing the vendor (the editor package's update mechanism)

The `editor` package's `vendor:` spec section (`vendor.npm: monaco-editor`)
makes the daily update flow check the npm registry. When a newer
monaco-editor release exists, `check-updates` emits a `vendor` entry and the
workflow runs `./scripts/refresh-editor.sh` — which npm-packs the latest
monaco-editor + TextMate stack, replaces the checked-in tree, and bumps
`pkg_manifest.version` — then opens a PR. **The PR is NOT auto-merged**: the
vendored diff is meant to be reviewed (a new Monaco can silently break the
hand-rolled textmate bridge or the wasm loader — CI can't catch that), so the
human merges it. The build-time guard (`editor/build.sh` compares the vendored
monaco version against `pkg_manifest.version`) fails the build on mismatch, so
the refresh PR's build only passes when the version and the files agree.

The script can also be run by hand:

```sh
./scripts/refresh-editor.sh
```

The TextMate stack (vscode-textmate, vscode-oniguruma) is refreshed alongside
monaco but does not drive the package version; the hand-rolled bridge
(`textmate/monaco-editor-textmate.js`) is never touched.
