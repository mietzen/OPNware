# CONTEXT.md — OPNware domain model

A personal FreeBSD package repository for OPNsense. The pipeline: package specs → payloads → packages → repo tree → GitHub Pages.

## Glossary

- **Package (pkg)** — a FreeBSD package in the opnware repo. Built from source, cross-compiled, or redistributed from upstream.
- **Package spec** — a package's `config.yml`: build config, manifest, service, redistribution.
- **Payload** — the staging root (a FreeBSD tree under `dist/pkg/`) that a build script fills before packing.
- **Packing module** — pkg-tool's `pack` interface: payload + package spec → `.pkg` + packagesite info.
- **Packagesite** — the repo index per ABI/arch: `packagesite.yaml` (accumulated), `packagesite.tzst`/`.pkg`, `meta.conf`.
- **Repo layout** — the published `FreeBSD:<abi>:<arch>/latest/` tree served via GitHub Pages.
- **Repo assembly** — turning built packages + repo config into the published repo tree.
- **Redistribution** — re-shipping an upstream FreeBSD pkg unchanged (redistribute configs).
- **ABI / arch** — FreeBSD major version (14/15) and machine architecture (amd64).
