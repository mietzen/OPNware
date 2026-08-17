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

## Development workflow (branch/PR per issue — mandatory)

Every issue is developed on its own branch, tested, merged via PR, and only
then deployed and e2e-tested on the test VM. Never commit directly to `main`;
never deploy from a local build.

1. **Branch**: `git switch -c <topic>/<issue-slug>` off `main` (one branch per
   issue; `main` stays green).
2. **Implement + test**: build the package locally to validate the payload
   (`./build.sh amd64 15` + `pkg-tool assemble-repo`), run `pytest
   pkg-tool/tests/` (install deps first: `pip install -e "pkg-tool[dev]"`).
3. **Test on the test VM**: install the built package on the `opnsense-test`
   VM (reachable via `ssh opnsense-test`; see "Testing & debugging on the VM")
   and exercise the change end-to-end before merging.
4. **PR**: open a PR (gh CLI) from the branch to `main`; CI runs the build
   matrix + assembly check on the PR. Iterate until green.
5. **AI review**: before merging, run the `/code-review` skill on the branch
   (two parallel sub-agents — Standards vs the issue spec, see "Review
   convention"). Address blocking findings with follow-up commits on the
   branch; re-run CI until green. Final review of implemented issues uses the
   `oracle` sub-agent.
6. **Merge**: merge the PR to `main` only after CI is green AND the AI review
   passed.
7. **Deploy**: pushing to `main` triggers the CI deploy to GitHub Pages — this
   is the ONLY deploy path. No local-build deploys.
8. **E2E on the test VM**: after the deploy job completes, point the VM's
   `/usr/local/etc/pkg/repos/opnware.conf` at the published repo
   (`https://mietzen.github.io/OPNware/${ABI}/latest`), `pkg update`, install
   the updated package, and verify the issue's acceptance criteria on the VM
   (WebUI via the 8443 tunnel + playwright, configd/rc service checks via ssh).
9. **Cleanup**: delete the merged branch; restore the VM repo config if it was
   pointed elsewhere during testing.

## Dependency update flow (automated)

Dependency bumps are driven by GitHub Actions + dependabot; bot PRs follow the
same branch/PR/review/merge rule as human work.

- **`pkg-tool check-updates`** (workflow `.github/workflows/update.yml`,
  nightly ~04:15 + on `workflow_dispatch`): scans every package spec and opens
  a PR bumping the `content:`/`version`/`vendor:` spec to the latest upstream.
  Version bumps for ordinary packages are auto-merged (`--auto`, gated on CI).
  `vendor:` bumps (monaco-editor, via `scripts/refresh-editor.sh`) are opened
  but NOT auto-merged — a human/agent must review the fetched-tree change
  manually. The `editor`/`monaco-editor` vendor layout and the CSP worker
  patch are documented in `docs/design/shared-editor-vendor.md`.
- **Dependabot** (`.github/dependabot.yml`, monthly, grouped): bumps
  `github-actions` action versions and `pkg-tool` pip deps. Its PRs are
  auto-merged by `.github/workflows/dependabot-automation.yml` (label-gated,
  CI-gated). Pinned-action and grouped-PR policy lives in dependabot.yml.
- When triaging a bot PR: the same standards apply — CI must be green and the
  change should be reviewed before it lands (auto-merge already enforces the
  CI gate; vendor/structural changes need explicit review).

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

## Plugin rename mechanics (learned on hardware, os-caddy-advanced)

Renaming a plugin is a **full-surface rename** — every one of these collides
with the official `os-<name>` if missed. The failure mode is silent: UI pages
load but settings don't save, or API endpoints 500.

- **Package identity**: `config.yml` → `pkg_manifest.name` (short name, pkg-tool
  prepends `os-`), `origin: opnware/os-<name>`. The version annotation file is
  `/usr/local/opnsense/version/<short-name>` (pkg-tool writes it) — this is what
  Firmware → Plugins reads.
- **MVC module dir** `OPNsense/<Module>`: PHP namespaces, class names, model
  files. **The model PHP/XML file names MUST match the class name** — the
  autoloader maps `OPNsense\X\Y` to `models/OPNsense/X/Y.php`. A renamed class
  with an old filename makes every API endpoint 500
  (`ReflectionException: Class ... does not exist`). Check every controller's
  `$internalModelClass`/`$internalServiceClass`/`$internalServiceTemplate`.
- **Config mount**: `CaddyAdvanced.xml` → `<mount>//OPNsense/caddyadvanced</mount>`.
  This is the key every script reads — `$config->OPNsense->caddyadvanced->...`.
  Missed references read null silently (dockerproxy-sync, setup, envfile,
  editor-save all broke this way).
- **Form field ids**: `forms/*.xml` `<id>` values carry the **model path
  prefix** (`caddyadvanced.general.enabled`), NOT the API URL. `getFormData()`
  (opnsense.js) builds the POST payload from the field id, and
  `ApiMutableModelControllerBase::setAction` reads `getPost($internalModelName)`.
  Mismatch = the whole form silently never saves (the enable checkbox was the
  symptom). The `frm_` prefix / `mapDataToFormUI` keys stay the tab-id, not the
  model name.
- **configd namespace**: action file `actions.d/actions_<ns>.conf` → `configctl
  <ns> ...`. Rename the file AND every `configdRun('caddy ...')` +
  `pluginctl -s <ns>` reference. Services page registration
  (`<name>_services()` in plugins.inc.d) must use the new namespace for its
  configd commands.
- **plugins.inc.d**: file `<ns>.inc` and function prefixes `<ns>_services()`,
  `<ns>_xmlrpc_sync()`, `<ns>_syslog()` (file basename == function prefix).
  XMLRPC section + `caddy_syslog()` facility must match the new mount/facility.
- **syslog facility / log module**: the `_syslog()` return key and the
  fragment's PROGRAM rewrite value must equal the new name or the Diagnostics
  viewer URL (`/ui/diagnostics/log/core/<name>`) resolves to an empty module.
- **Menu/ACL**: menu tag id + `VisibleName`, ACL page id + URL patterns. Keep
  the display name readable (`<CaddyAdvanced VisibleName="Caddy Advanced">`).
- **State dirs**: `/var/db/os-caddy-advanced`, `/var/run/os-caddy-advanced` in
  every controller const and script — pkg does not own these (created at
  runtime), so no file-ownership conflict, but both old and new must agree.
- **pkg trigger**: rename `os-<pkg>-<thing>.ucl`; script paths inside.

## Service control / start-stop-restart (learned on hardware)

- **Buttons render into `#service_status_container`** (the page header, from
  `layouts/default.volt`) via `updateServiceControlUI('<name>')` — NOT into the
  plugin's own status box. It only renders when `/api/<name>/service/status`
  returns `running` or `stopped`; `disabled` → no buttons.
- **`*_services()` gates registration on `enabled == 1` by default** (matches
  core plugins). If you want the start button available while disabled,
  register unconditionally and override `statusAction()` in the service
  controller to report `stopped` (not `disabled`) when down.
- **Do NOT override `reconfigureAction()` and call `$this->reload()`** — that
  method does not exist on `ApiMutableServiceControllerBase` (was a silent
  no-op: template regenerated, service never started). Replicate the base
  logic: if enabled → `start` when not running / `reload` when running, else
  `stop`.
- The base `statusAction()` contract: parse `configdRun('<ns> status')` output
  for "is running" / "not running", return `{status, widget:{caption_*}}`.
- The rc.d script refuses `service caddy start` when `caddy_enable="NO"`
  (correct rc.subr behavior) — the template writes this from the enabled
  setting. A "can't start" report is often just the disabled state.

## Testing & debugging on the VM (learned on hardware)

- **tcsh quirk**: the VM shell is tcsh — `2>/dev/null`, `&` backgrounding, and
  nested quotes in `ssh '...'` break with "Ambiguous output redirect". Write a
  script locally, `scp` it, run `sh /tmp/script.sh`.
- **Local repo serving**: macOS firewall blocks inbound to a host-side
  `http.server` — serve the repo ON the VM instead: copy the assembled
  `pages-check/` to `/tmp/opnware-repo`, run `python3 -m http.server 8080`
  there, point `/usr/local/etc/pkg/repos/opnware.conf` at
  `http://127.0.0.1:8080/${ABI}/latest`. Restore the published URL after.
- **Corrupt pkg DB**: interrupted updates leave
  `sqlite error ... UNIQUE constraint failed: packages.manifestdigest`.
  Fix: `sudo rm -f /var/db/pkg/repos/opnware/db /var/db/pkg/repos/opnware/db-journal`
  then `pkg update`.
- **Repo assembly**: every `.pkg` needs its own directory with its own
  `packagesite_info.json` (CI artifacts are per-job dirs). Dumping many pkgs
  into one dir with one info file duplicates entries in packagesite.
- **pkg install crash on conflicts**: a manifest `conflicts: [os-caddy]` field
  breaks install when the target isn't in the local DB (`NOT NULL constraint
  failed: pkg_conflicts.conflict_id`). Carry the conflict annotation-only
  (`product_conflicts`).
- **API probing**: `curl -u opencode:opencode` returns 401 (needs session
  cookie + CSRF). Use playwright with a real login for API/UI verification.
- **PHP/JS source of truth is the VM** (core files aren't in this repo):
  `ApiMutableServiceControllerBase.php`, `ControllerBase.php` (`parseFormNode`),
  `Backend.php` (`configdRun`/`configdpRun`), `opnsense_ui.js`
  (`updateServiceControlUI`, `saveFormToEndpoint` — the 4th arg
  `disable_dialog` suppresses the validation BootstrapDialog),
  `opnsense.js` (`getFormData`), `log_matcher.py`, `queryLog.py`.
- **Log viewer severity**: the Diagnostics log viewer defaults to `Warning`
  severity for unknown services (LogController switch) — caddy/homer logs are
  all `Informational`, so the viewer shows nothing until you select
  "Informational" in the severity filter. Same for homer; not a plugin bug.
- **Service registration check**: `pluginctl -l` lists configure hooks, NOT
  services. Test with `configctl <ns> status` / `pluginctl -s <ns> status`.
- **PHP foreach reference footgun**: `foreach ($form['tabs'] ?? [] as &$tab)`
  silently mutates a temporary — the `??` makes a copy; reference iteration
  never touches the original. Use a plain `foreach` (guarded with isset first).

## Where to look for answers

- **OPNsense dev manual** (authoritative): https://docs.opnsense.org/develop.html
  and https://docs.opnsense.org/development/backend/legacy.html (plugin `.inc`
  hooks, configd actions, syslog-ng).
- **Official plugins repo**: `https://github.com/opnsense/plugins` — mirror the
  exact naming/structure (the official `os-caddy` lives at `www/caddy`). Shallow
  clone to `/tmp` when needed.
- **FreeBSD ports**: `https://github.com/freebsd/freebsd-ports` — `www/caddy/`
  has the rc script + Makefile (CustomVersion ldflag) that plugins should mirror.
- **Core PHP/JS implementation**: read it on the VM under
  `/usr/local/opnsense/mvc/app/...` and `/usr/local/opnsense/www/js/` — the
  class/method names above are the anchors. `grep -rn` is the fastest way to
  resolve the exact contract (e.g. `updateServiceControlUI`, `getFormData`,
  `fetch_log_filenames`).
- **pkg/package format**: `pkg rquery`/`pkg query` format flags (`%n %o %v %L
  %C`), `tar -xOf <pkg> +MANIFEST` to inspect a built package, and pkg-tool's
  own tests in `pkg-tool/tests/` for the packing seams.
