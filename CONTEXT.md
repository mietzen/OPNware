# CONTEXT.md — OPNware domain model

A personal FreeBSD package repository for OPNsense. The pipeline: package specs → payloads → packages → repo tree → GitHub Pages.

## Glossary

- **Package (pkg)** — a FreeBSD package in the opnware repo. Built from source, cross-compiled, or redistributed from upstream.
- **Package spec** — a package's `config.yml`: build config, manifest, redistribution. Plain packages ship no service/rc.d machinery (retired, ticket #205); payloads stage on FreeBSD default paths.
- **Payload** — the staging root (a FreeBSD tree under `dist/pkg/`) that a build script fills before packing.
- **Packing module** — pkg-tool's `pack` interface: payload + package spec → `.pkg` + packagesite info.
- **Packagesite** — the repo index per ABI/arch: `packagesite.yaml` (accumulated), `packagesite.tzst`/`.pkg`, `meta.conf`.
- **Repo layout** — the published `FreeBSD:<abi>:<arch>/latest/` tree served via GitHub Pages.
- **Repo assembly** — turning built packages + repo config into the published repo tree.
- **Redistribution** — re-shipping an upstream FreeBSD pkg unchanged (redistribute configs).
- **ABI / arch** — FreeBSD major version (15) and machine architecture (amd64).
- **LOCALBASE** — the FreeBSD default prefix (`/usr/local`): binaries in `bin/`, configs in `etc/`, data in `share/`.
- **OPNsense plugin (os-* plugin)** — an OPNsense MVC (Phalcon PHP) plugin: `config.xml` model, models/controllers/services, menu + ACL, managed via the WebUI and configd.
- **os-caddy** — the custom OPNsense plugin for Caddy (WebUI-managed, user-owned Caddyfile, module management); depends on the plain caddy pkg.
- **os-homer** — the custom OPNsense plugin for Homer (WebUI-managed, served via caddy on 9443); replaces the plain homer pkg.
