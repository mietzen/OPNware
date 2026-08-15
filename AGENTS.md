# AGENTS.md

## Agent skills

### Issue tracker

Issues live as GitHub issues (gh CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical labels: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Review convention

Final reviews of implemented issues use the `oracle` sub-agent.

## OPNsense development reference

The OPNsense development manual is the authoritative reference for plugin
internals: https://docs.opnsense.org/develop.html — in particular the backend
pages (https://docs.opnsense.org/development/backend/legacy.html) which cover
plugin `.inc` hooks (`<name>_services()`, `<name>_configure()`,
`<name>_syslog()`, ...), configd actions, and syslog-ng integration.

## Plugin architecture (learned on hardware)

- **Templates**: `pkgs/<plugin>/src/opnsense/service/templates/OPNsense/<Plugin>/`
  with `+TARGETS` mapping template paths to install locations. Regenerate via
  `sudo configctl template reload OPNsense/<Plugin>` or `configctl <plugin> reconfigure`.
- **rc scripts**: `src/usr/local/etc/rc.d/<plugin>`; rc vars generated into
  `/etc/rc.conf.d/<plugin>` by the template. rc.d file is staged with a
  double-prefix and relocated by build.sh (see `pkgs/os-homer/build.sh`).
- **Configd actions**: `src/opnsense/service/conf/actions.d/<plugin>.conf`.
  `script_output` actions: configd swallows output on non-zero exit
  ("Execute error") — scripts must write results to a state file and the
  controller falls back to it.
- **MVC form fields** carry dotted ids (`homer.general.Port`) and **no `name`
  attribute**; the form element is `frm_<tab-id>` (e.g. `frm_general-settings`).
  `mapDataToFormUI` keys are the `frm_` prefix (`frm_general` matches
  `frm_general-settings` via split('-')[0]). Read fields by id, never by name.
- **Volt page CSS**: `content-box tab-content` wrappers must have NO top
  padding and tabs must have `margin-bottom: 0` — otherwise a visible band
  appears between the tab underline and the form (core IPsec pattern).
  Headings need `margin-top: 0` (theme gives h1-h3 18px top margin).
- **bootstrap-select**: core auto-initializes `.selectpicker` on window load;
  the instance data key is `selectpicker` (NOT `bs.select`). When options are
  added async, check `$sel.data('selectpicker')` before refresh/init.
- **Monaco + jstree AMD conflict**: monaco's `vs/loader.js` defines a global
  `define`, which swallows other AMD-capable libs (jstree) into AMD mode.
  Load jstree BEFORE monaco's loader. jstree appends its context menu to
  `<body>` with z-index auto — it renders behind Monaco's stacking context;
  needs `.vakata-context { z-index: 10000 }`.
- **Logging**: OPNsense plugins ship static syslog-ng fragments to
  `/usr/local/etc/syslog-ng.conf.d/<name>.conf` (the syslog-ng.conf glob
  `@include` picks them up). The fragment tails the service's log file /
  unix socket and rewrites into `/var/log/<name>/<name>_YYYYMMDD.log`
  (RFC5424) which the core Diagnostics viewer (`/ui/diagnostics/log/core/<name>`)
  parses. `log_matcher.py` resolves module dir `/var/log/<module>/<module>.log`.
  Register `<name>_syslog()` in plugins.inc.d for remote targets.
- **pkg triggers**: `/usr/local/share/pkg/triggers/*.ucl` fire immediately at
  the end of any pkg transaction that installs/upgrades/removes a file matching
  `path:`. They only activate once installed by their owning package (manual
  copies are ignored — pkg tracks ownership in the DB). Use for
  "dependency upgraded → react now" (e.g. caddy binary replaced → rebuild
  modules), with the periodic hook kept as a fallback.
- **Testing on hardware**: VMs `opnsense-test` (OPNsense 26.7) and
  `debian-test`; WebUI at `https://127.0.0.1:8443` via SSH tunnel
  (user `opencode`/`opencode`, self-signed). Deploy: `pkg update` then
  `pkg install -fy opnware/<plugin>` (explicit origin — name lookup hits the
  official plugin), then `sudo configctl webgui restart`. Screenshots via
  playwright capture script in `/var/folders/.../T/uipass/capture.js`; this
  model has no image input, so visual checks go through a multimodal-looker
  subagent. Restore both VM snapshots after testing.
