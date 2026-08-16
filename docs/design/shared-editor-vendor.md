# Shared vendored editor asset: Monaco + TextMate (os-caddy-advanced and os-homer)

The OPNsense web UI pages in this repo render a real code editor by shipping a
**shared, vendored** copy of the Monaco editor plus the TextMate grammar
support that gives the Caddyfile (and, for os-homer, YAML) its syntax
highlighting. Nothing is loaded from a CDN — every byte is installed with the
plugin package and served from the WebUI origin.

This document is the reference for how a plugin consumes the asset. Both the
os-caddy-advanced Caddyfile editor and the os-homer YAML config editor follow it.

## What is vendored and where

Source of truth: **`pkgs/monaco-editor/`** — the package owns the asset, but
the payload is **built in CI, not checked in**. `build.sh` npm-packs
monaco-editor (at the pinned version) plus the TextMate stack, applies the
CSP worker patch, and stages everything into the payload. The only checked-in
files are the hand-written ones in `pkgs/monaco-editor/src/`:

```
pkgs/monaco-editor/
├── config.yml                         # pins monaco-editor version (pkg_manifest.version)
├── build.sh                           # npm-pack → patch → stage → pkg-tool pack
└── src/                               # hand-written artifacts (checked in, tiny)
    ├── patch-csp-worker.py            # codemod: applies the CSP worker patch to the pristine tree
    ├── editor.worker.bootstrap.js     # same-origin classic worker (CSP-safe)
    ├── monaco-editor-textmate.js      # hand-rolled bridge: TM grammar as a Monaco token provider
    └── caddyfile.tmLanguage.json      # TextMate grammar, caddyserver/vscode-caddyfile (source.Caddyfile)
```

The build-time payload layout under `/usr/local/opnsense/www/js/vendor/`:

```
vendor/
├── monaco/
│   ├── package.json                   # monaco-editor provenance (fetched)
│   └── vs/                            # monaco-editor standalone min build (fetched, then patched)
│       ├── loader.js                  # Monaco AMD loader (defines global require/define)
│       └── editor/editor.main.js (+ css, worker)   # patched for CSP
├── caddyfile.tmLanguage.json          # from src/ (checked in)
└── textmate/
    ├── vscode-textmate/               # npm vscode-textmate (fetched)
    ├── vscode-oniguruma/release/      # oniguruma→wasm bindings + onig.wasm (fetched)
    └── monaco-editor-textmate.js      # from src/ (checked in)
```

> **Why a hand-rolled bridge instead of the npm `monaco-editor-textmate`
> package?** The npm package (4.x) pins the abandoned
> `monaco-textmate`/`onigasm` chain and cannot run in a plain browser page.
> `monaco-editor-textmate.js` implements the same
> `wireTmGrammars(monaco, registry, languages)` contract on top of the modern
> `vscode-textmate` + `vscode-oniguruma` stack (the stack VS Code itself uses
> today). Same API, current engine, no dead deps.

## How the vendor reaches the WebUI — the shared `monaco-editor` package

OPNsense serves `/opnsense/www/js/...` as the `/ui/js/...` URL prefix, so the
vendor tree must land under `/usr/local/opnsense/www/js/vendor/`. The files
are owned by the **`monaco-editor` package** (`pkgs/monaco-editor/`), a plain
payload package whose build.sh fetches the npm releases, applies the patch
and stages the payload:

```bash
# pkgs/monaco-editor/build.sh (abridged)
npm pack "monaco-editor@${MONACO_VERSION}" ...   # MONACO_VERSION from pkg_manifest.version
npm pack "vscode-textmate@9.3.2" ...
npm pack "vscode-oniguruma@2.0.1" ...
cp src/editor.worker.bootstrap.js src/monaco-editor-textmate.js src/caddyfile.tmLanguage.json ...
python3 src/patch-csp-worker.py "${WORK}"        # applies the CSP patch to the pristine tree
pkg-tool pack ...
```

Both plugins declare it as a pkg dependency
(`deps: monaco-editor: opnware/monaco-editor`), so `pkg` installs it first
and no plugin payload ever owns the vendor files. This is deliberate: shipping the
same files in two plugin payloads would make `pkg` refuse co-installation
(duplicate file ownership). Never copy the vendor into a plugin payload —
change the `monaco-editor` package instead.

> **Vendored patch — CSP-safe Monaco workers.** OPNsense's CSP
> (`script-src 'self' 'unsafe-inline' 'unsafe-eval'`, no `worker-src blob:`)
> blocks Monaco's default blob: web workers, and Monaco's main-thread
> fallback freezes the editor UI on model changes. `editor.main.js` is
> therefore patched so `MonacoEnvironment.getWorker` returns a classic
> same-origin worker loading `editor/editor.worker.bootstrap.js`, which
> `importScripts` the vendored AMD loader and boots `vs/editor/editor.worker`
> (module id re-based via `require.config({ baseUrl })`). The patch must live
> in `editor.main.js` itself: Monaco instantiates its workers during module
> evaluation, before any page-level `MonacoEnvironment` override could take
> effect. The patch is applied by `src/patch-csp-worker.py` **at build time**
> (never copied from a checked-in tree), so a version bump can't silently lose
> it — the codemod fails the build if the pristine patterns are absent. Keep
> the version contract: base version must equal the monaco release, a `_N`
> revision suffix may be used for package-only changes.

## Caddy editor tree

The editor manages a flat tree: `Caddyfile` plus `conf.d/*.caddy`. The seed
`Caddyfile` is the single line `import conf.d/*.caddy` — a native, non-recursive
Caddy glob, so the tree is flat by construction and no generated import index
exists. The `Caddyfile` remains user-owned.

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

## Refreshing the vendor (the monaco-editor package's update mechanism)

The `monaco-editor` package's `vendor:` spec section
(`vendor.npm: monaco-editor`) makes the daily update flow check the npm
registry. When a newer monaco-editor release exists, `check-updates` emits a
`vendor` entry and the workflow runs `./scripts/refresh-editor.sh <version>`
— which bumps `pkg_manifest.version` (a **plain version bump; the build
fetches the release**) — then opens a PR. **The PR is NOT auto-merged**: a
new Monaco release is meant to be reviewed (a new Monaco can silently break
the hand-rolled textmate bridge or the wasm loader — CI can't catch that), so
the human merges it. The build-time codemod
(`src/patch-csp-worker.py`) fails the build if the pristine patch patterns
change, so the refresh PR's build only passes when the patch still applies.

The script can also be run by hand:

```sh
./scripts/refresh-editor.sh          # bump to the latest npm release
./scripts/refresh-editor.sh 0.57.0   # bump to a specific release
```

The TextMate stack (vscode-textmate, vscode-oniguruma) is pinned in
`build.sh` (refreshed alongside monaco but does not drive the package
version); the hand-rolled bridge (`src/monaco-editor-textmate.js`) is never
touched by a refresh.
