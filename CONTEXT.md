# CONTEXT.md — OPNware domain model

A personal FreeBSD package repository for OPNsense. The pipeline: package specs → payloads → packages → repo tree → GitHub Pages.

## Glossary

- **Package (pkg)** — a FreeBSD package in the opnware repo. Built from source, cross-compiled, or redistributed from upstream.
- **Package spec** — a package's `config.yml`: build config, manifest, and one of redistribution, a `plugin:` section, or a `content:` section. Plain packages ship no service/rc.d machinery (retired, ticket #205); payloads stage on FreeBSD default paths.
- **Plugin spec** — the `plugin:` section of a package spec: `opnsense_version` (the OPNsense ABI, e.g. 26.7), `tier`, `conflicts` (pkg-native). Pack derives the `os-` prefix, the `/usr/local/opnsense/version/<name>` annotation and the configd lifecycle hooks from the payload.
- **Content** — the `content:` section (`repo` + `version`) of a plugin spec: upstream bundled content (e.g. the Homer dashboard inside os-homer). `check-updates` checks it even for plugin specs; `bump` rev-bumps the package version when it changes.
- **Package revision** — the `_N` suffix on a package version (FreeBSD convention): bumped when bundled content changes, so an updated bundle ships as a visibly different package revision without changing the plugin's version base.
- **Payload** — the staging root (a FreeBSD tree under `dist/pkg/`) that a build script fills before packing.
- **Packing module** — pkg-tool's `pack` interface: payload + package spec → `.pkg` + packagesite info.
- **Packagesite** — the repo index per ABI/arch: `packagesite.yaml` (accumulated), `packagesite.tzst`/`.pkg`, `meta.conf`.
- **Repo layout** — the published `FreeBSD:<abi>:<arch>/latest/` tree served via GitHub Pages.
- **Repo assembly** — turning built packages + repo config into the published repo tree.
- **Redistribution** — re-shipping an upstream FreeBSD pkg unchanged (redistribute configs).
- **ABI / arch** — FreeBSD major version (15) and machine architecture (amd64).
- **LOCALBASE** — the FreeBSD default prefix (`/usr/local`): binaries in `bin/`, configs in `etc/`, data in `share/`.
- **OPNsense plugin (os-* plugin)** — an OPNsense MVC (Phalcon PHP) plugin: a model XML (config mount `//OPNsense/<name>`), controllers/services, menu + ACL, managed via the WebUI and configd. There is no `config.xml` — the model XML replaces it. Packed with the `os-` prefix via pkg-tool's plugin-package support.
- **os-caddy-advanced** — the custom OPNsense plugin for Caddy (WebUI-managed, user-owned Caddyfile, module management); depends on the plain caddy pkg.
- **os-homer** — the custom OPNsense plugin for Homer (WebUI-managed, served via caddy on 9443); replaces the plain homer pkg; bundled dashboard tracked via `content:`.
- **editor** — the shared package owning the vendored Monaco + TextMate editor tree served at `/usr/local/opnsense/www/js/vendor`; os-caddy-advanced and os-homer depend on it; its version tracks the vendored monaco-editor release. A `vendor:` spec section points the update flow at the npm registry: a newer release opens a refresh PR (via `scripts/refresh-editor.sh`) that is reviewed, not auto-merged.
