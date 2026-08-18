# Shared vendored editor asset: Monaco + Caddyfile Monarch grammar (os-caddy-advanced and os-homer)

The OPNsense web UI pages in this repo render a real code editor by shipping a
**shared, vendored** copy of the Monaco editor. Caddyfile syntax highlighting
comes from a hand-written **Monarch** grammar built into the shared package;
os-homer's YAML editor uses Monaco's built-in YAML basic language. Nothing is
loaded from a CDN — every byte is installed with the plugin package and served
from the WebUI origin.

This document is the reference for how a plugin consumes the asset. Both the
os-caddy-advanced Caddyfile editor and the os-homer YAML config editor follow it.

## What is vendored and where

Source of truth: **`pkgs/monaco-editor/`** — the package owns the asset, but
the payload is **built in CI, not checked in**. `build.sh` npm-packs
monaco-editor (at the pinned version) and stages the (unpatched) tree into the
payload. The only checked-in files are the hand-written ones in
`pkgs/monaco-editor/src/`:

```
pkgs/monaco-editor/
├── config.yml                         # pins monaco-editor version (pkg_manifest.version)
├── build.sh                           # npm-pack → stage → pkg-tool pack
└── src/                               # hand-written artifacts (checked in, tiny)
    └── caddyfile.js                   # Caddyfile Monarch grammar (registers 'caddyfile' + 'opnware-json')
```

The build-time payload layout under `/usr/local/opnsense/www/js/vendor/`:

```
vendor/
├── monaco/
│   ├── package.json                   # monaco-editor provenance (fetched)
│   └── vs/                            # monaco-editor standalone min build (fetched, unpatched)
│       ├── loader.js                  # Monaco AMD loader (defines global require/define)
│       └── editor/editor.main.js (+ css, worker)
└── caddyfile.js                       # from src/ (checked in)
```

> **Why Monarch instead of TextMate?** The previous setup shipped the TextMate
> stack (vscode-textmate + vscode-oniguruma + the oniguruma wasm) plus a
> hand-rolled bridge (`monaco-editor-textmate.js`) that wired a TextMate
> grammar into Monaco as a token provider. Two pain points drove the change:
> the bridge had to map each token's scope *stack* to a single dotted scope
> string (Monaco's theme trie splits only on `.`, so a space-joined stack never
> matched and every token fell back to `mtk1`), and the stock vs/vs-dark themes
> contain no `entity.*`/`support.*` rules, so the bridge also had to register
> extended themes (`opnware-vs`/`opnware-vs-dark`). Monarch is built into
> Monaco: synchronous, no wasm, no extra runtime, and the grammar can simply
> emit tokens that already exist in the stock themes.
>
> Trade-off: Monarch has no backreferences, so a `<&lt;&lt;TAG` heredoc with an
> unknown tag cannot match its terminator to the opening tag — it terminates on
> the first line that is a single bare word. The five well-known heredoc tags
> (CSS, HTML, JS|JAVASCRIPT, JSON, XML) embed their language via `nextEmbedded`
> and are terminated correctly. JSON is not a basic Monaco language (it needs
> the worker), so `&lt;&lt;JSON` heredocs embed `opnware-json`, a small Monarch
> JSON tokenizer registered by the same `caddyfile.js` module. All emitted
> tokens (`string.key.json`, `keyword.json`, ...) exist in the stock themes.

## How the vendor reaches the WebUI — the shared `monaco-editor` package

OPNsense serves `/opnsense/www/js/...` as the `/ui/js/...` URL prefix, so the
vendor tree must land under `/usr/local/opnsense/www/js/vendor/`. The files
are owned by the **`monaco-editor` package** (`pkgs/monaco-editor/`), a plain
payload package whose build.sh fetches the npm release and stages the payload:

```bash
# pkgs/monaco-editor/build.sh (abridged)
npm pack "monaco-editor@${MONACO_VERSION}" ...   # MONACO_VERSION from pkg_manifest.version
cp src/caddyfile.js "${WORK}/caddyfile.js"       # the Monarch grammar module
pkg-tool pack ...
```

Both plugins declare it as a pkg dependency
(`deps: monaco-editor: opnware/monaco-editor`), so `pkg` installs it first
and no plugin payload ever owns the vendor files. This is deliberate: shipping the
same files in two plugin payloads would make `pkg` refuse co-installation
(duplicate file ownership). Never copy the vendor into a plugin payload —
change the `monaco-editor` package instead.

> **How the editor works under the OPNsense CSP.** OPNsense's CSP
> (`script-src 'self' 'unsafe-inline' 'unsafe-eval'`, no `worker-src blob:`)
> blocks Monaco's default blob: web workers and its inline `data:font/ttf`
> codicon font. The editor pages therefore ship the vendored tree unpatched
> and extend the CSP **per-controller** (the `content_security_policy` merge
> in `ControllerBase`: `worker-src 'self' blob:` and `font-src 'self' data:`),
> so Monaco's native blob: workers and inline codicon font work as-is. This
> replaced the earlier build-time codemods that edited the pristine tree; a
> version bump can no longer silently lose a patch, at the cost of requiring
> the page controller to carry the CSP extension. Keep the version contract:
> base version must equal the monaco release, a `_N` revision suffix may be
> used for package-only changes.

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
            caddyfile: '/ui/js/vendor/caddyfile'
        }
    });
</script>
```

2. Require the grammar module alongside `editor.main` — a loaded dependency of
   the `require`, so the `caddyfile` and `opnware-json` languages are
   registered before the editor is created with `language: 'caddyfile'`:

```js
require(['vs/editor/editor.main', 'caddyfile'], function (monaco) {
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
});
```

Key points for a consumer:

- The grammar module is a normal AMD module: `define(['vs/editor/editor.main'],
  factory)` — the factory receives `monaco` and calls
  `monaco.languages.register` / `setLanguageConfiguration` /
  `setMonarchTokensProvider`. No fetch, no wasm, no async wiring; a missing
  module fails the `require` loudly instead of silently degrading to no
  highlighting.
- **Token/theme contract (why no theme extension is needed):** Monarch emits
  each token as a *single dotted token string* (not a scope stack), and Monaco
  resolves the color by walking the theme trie longest-first. The grammar only
  emits tokens that exist in the stock `vs`/`vs-dark` themes — `comment`,
  `keyword`, `string`, `number`, `type`, `variable`, `constant`,
  `delimiter.curly` — so the editor pages use the stock theme names. Legacy
  `opnware-vs`/`opnware-vs-dark` values stored by the old bridge-era UI are
  mapped back to `vs`/`vs-dark`.
- The grammar's tokenizer mirrors the upstream caddyserver/vscode-caddyfile
  TextMate grammar: directives are `keyword`, the domain/address side of a
  site block is `type`, matchers are `variable`, and content-type / HTTP-status
  / placeholder rules cover argument positions.

> **Why the codicon font renders correctly?** OPNsense's CSP (`default-src
> 'self'`, no `font-src`) blocks Monaco's default `data:font/ttf` codicon font
> (used for the folding chevrons and other UI icons), so folding controls
> would render as a literal `EAB4` glyph. The editor pages extend the CSP
> per-controller with `font-src 'self' data:`, so the inline font is allowed
> and the vendored tree ships unpatched (see the CSP note above).

## Updating the editor (manual, pinned version)

The `monaco-editor` version is **pinned** — the daily update flow
(`pkg-tool check-updates`, `.github/workflows/update.yml`) does NOT propose
monaco bumps. There is no refresh script and no npm vendor adapter; the package
spec carries no `vendor:` section. Updating is a deliberate, manual act:

1. Bump `pkg_manifest.version` in `pkgs/monaco-editor/config.yml`. The version
   contract is preserved: the base version must equal the monaco release, a
   `_N` suffix marks package-only changes. `build.sh` derives the npm version
   by stripping the `_N` suffix and fetches the pinned release at build time,
   so a manual bump still produces a working package.
2. Build locally (`./build.sh amd64 15`) and inspect the payload — the
   vendored tree is fetched fresh, so a new release can silently break the
   hand-written Monarch grammar (`src/caddyfile.js`) or the CSP assumptions
   the editor pages rely on. CI cannot catch highlighting or CSP regressions.
3. Install on the test VM and **visually verify both editors** (the
   os-caddy-advanced Caddyfile editor and the os-homer YAML editor) before
   merging the bump PR.

The grammar (`src/caddyfile.js`) is never touched by a bump; it is
monaco-version-independent (Monarch API is stable).
