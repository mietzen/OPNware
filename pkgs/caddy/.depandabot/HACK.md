# Dependabot Hack

We trick Dependabot into tracking the caddy plugin modules that are built into the
OPNsense caddy package: a fake Go module (`go.mod` + `deps.go` with the `dependabot`
build tag) mirrors `CADDY_PLUGINS` in `pkgs/caddy/build.sh`. When Dependabot opens a
`go` PR for one of these modules, `dependabot-automation.yml` bumps caddy's
enhancement version in `pkgs/caddy/config.yml`, forcing a rebuild (`xcaddy` pulls the
latest plugin versions, so the new plugin lands in the package).

Keep `deps.go` imports and the `go.mod` requires in sync with `CADDY_PLUGINS`, and run
`go mod tidy` after any change so `go.sum` stays complete.
