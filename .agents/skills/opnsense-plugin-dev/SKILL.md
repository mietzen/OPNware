---
name: opnsense-plugin-dev
description: Develop, debug, refactor, and review OPNsense plugins in OPNware (MVC models, Volt views, controllers, configd actions, service lifecycle, syslog-ng fragments, rc scripts, and packaging). Use when creating new plugins, modifying forms/models, adding configd actions, wiring service controls, fixing UI styling, or debugging FreeBSD/OPNsense backend behaviors.
---

# OPNsense Plugin Development Guide & Standards

Authoritative blueprint and standards for developing OPNsense plugins within the OPNware repository. Complements the [OPNsense Developer Manual](https://docs.opnsense.org/develop.html) with hard-won operational patterns and invariants learned on FreeBSD hardware.

---

## 1. Plugin Architecture Flow

An OPNsense plugin spans eight cooperating layers. Every component must align with the plugin namespace:

```
[ WebUI / Volt View ]
       │  (AJAX POST/GET)
       ▼
[ ApiController / ModelController ]
       │  (Model Read/Write / Backend::configdRun)
       ▼
[ Model XML & Form XML ] ────► [ config.xml (//OPNsense/<module>) ]
       │
       ▼
[ configd Action (/usr/local/opnsense/service/conf/actions.d/) ]
       │  (Spawns backend script or template reload)
       ▼
[ Backend Script / Service Template (+TARGETS -> /etc/rc.conf.d/) ]
       │  (Generates runtime config, calls FreeBSD service)
       ▼
[ FreeBSD rc.d Script (/usr/local/etc/rc.d/<name>) ]
       │  (Starts/stops daemon via rc.subr)
       ▼
[ syslog-ng Pipeline (/usr/local/etc/syslog-ng.conf.d/<name>.conf) ]
       │  (Captures socket/log, rewrites PROGRAM to <name>)
       ▼
[ RFC5424 Log File -> /var/log/<name>/<name>_YYYYMMDD.log ]
```

---

## 2. Step-by-Step Plugin Implementation

### Step 1: Model & Schema Definition
1. **Model Class**: `src/opnsense/mvc/app/models/OPNsense/<Module>/<Model>.php`
   - Must extend `OPNsense\Base\BaseModel`.
   - Class name MUST strictly match filename for PSR-4 autoloading.
2. **Model XML**: `src/opnsense/mvc/app/models/OPNsense/<Module>/<Model>.xml`
   - Mount path must be unique: `<mount>//OPNsense/<module></mount>`.
   - Use standard field types: `BooleanField`, `TextField`, `IntegerField`, `OptionField`, `CSVListField`.
   - **Rule**: Do not place `<AsList>` on `TextField` (no-op in BaseModel).

### Step 2: Form Definitions
1. **Form XML**: `src/opnsense/mvc/app/models/OPNsense/<Module>/forms/<form>.xml`
2. **Field IDs**: MUST carry the exact dotted model path:
   ```xml
   <field>
       <id><module>.<tab>.<field></id>
       <label>Setting Name</label>
       <type>text</type>
   </field>
   ```
3. **Form Naming Contract**:
   - Volt forms use `id="frm_<tab-id>"` (e.g., `frm_general-settings`).
   - `mapDataToFormUI` matches keys by the `frm_` prefix (`frm_general` maps to `frm_general-settings` via `split('-')[0]`).
   - Fields have NO `name` attribute — `getFormData()` reads strictly by element `id`.

### Step 3: Controllers
1. **Model Controller (General / Settings)**:
   - Inherits `OPNsense\Base\ApiMutableModelControllerBase`.
   - Defines `$internalModelClass`, `$internalModelName`, `$internalModelPath`.
   - Standard `getAction()` and `setAction()` serialize and deserialize model data automatically.
2. **Service Controller (Lifecycle)**:
   - Inherits `OPNsense\Base\ApiMutableServiceControllerBase`.
   - Defines `$internalServiceClass`, `$internalServiceTemplate`, `$internalServiceEnabled`.
   - **`statusAction()` Contract**: Must return `['status' => 'running'|'stopped', 'widget' => [...]]`. Return `'stopped'` (not `'disabled'`) when the daemon is down so header action buttons render in `#service_status_container`.
   - **Do NOT override `reconfigureAction()` to call `$this->reload()`** — that method does not exist on `ApiMutableServiceControllerBase`. Replicate standard lifecycle: if enabled -> start/reload, else stop.

### Step 4: Service Orchestration (`plugins.inc.d`)
Create `src/etc/inc/plugins.inc.d/<name>.inc`:
- **Basename MUST match function prefix** (`<name>_services()`, `<name>_configure()`, `<name>_syslog()`, `<name>_xmlrpc_sync()`).
- Always initialize array before appending:
  ```php
  function <name>_services()
  {
      $services = array();
      $services[] = array(
          'description' => gettext('<Display Name>'),
          'configd' => array(
              'restart' => array('<name> restart'),
              'start' => array('<name> start'),
              'stop' => array('<name> stop'),
          ),
          'name' => '<name>',
          'pidfile' => '/var/run/<name>/<name>.pid'
      );
      return $services;
  }
  ```

### Step 5: Configd Actions & Backend Execution
Create `src/opnsense/service/conf/actions.d/actions_<name>.conf`:
1. Use `type:script` for mutations and `type:script_output` for queries/readouts.
2. Explicitly call `/usr/local/bin/php` with absolute script paths.
3. **Configd Exit Contract**:
   - On non-zero script exit, configd returns `"Execute error"` and swallows stdout.
   - Scripts performing validation or mutations must write execution results to a JSON status file (`/var/db/<plugin>/<name>_status.json`).
   - Controllers must fall back to reading the status file when configd output is empty or reports `"Execute error"`.
4. Escape all dynamic CLI parameters with `escapeshellarg()`.

### Step 6: Templates & FreeBSD rc.d
1. **Templates**: `src/opnsense/service/templates/OPNsense/<Module>/`
   - File `+TARGETS` maps template files to destination paths (typically `/usr/local/etc/<name>/...` or `/etc/rc.conf.d/<name>`).
   - Template variables read directly from OPNsense config tree: `OPNsense.<module>.<section>.<field>`.
2. **FreeBSD rc Script**: `src/usr/local/etc/rc.d/<name>`
   - Follows standard FreeBSD `rc.subr` structure (`rcvar`, `load_rc_config`, `run_rc_command`).
   - Honor `<name>_enable="YES"` generated into `/etc/rc.conf.d/<name>`.

### Step 7: Logging & Diagnostics Integration
Create `src/etc/syslog-ng.conf.d/<name>.conf`:
1. Define Unix datagram socket source (`/var/run/<name>/log.sock`) and stdout fallback file.
2. Rewrite `PROGRAM` header to match plugin name: `rewrite { set("<name>" value("PROGRAM")); };`.
3. Output to `/var/log/<name>/<name>_${YEAR}${MONTH}${DAY}.log` with `flags(syslog-protocol)`.
4. Ensure `<name>_syslog()` in `plugins.inc.d/<name>.inc` exports matching facility.
5. Core Diagnostics log viewer URL `/ui/diagnostics/log/core/<name>` will parse and display logs.

### Step 8: Volt Views & CSS Rules
1. **Tab Underline / Gap Prevention**:
   - Tab wrappers must use `.content-box.tab-content` with NO top padding.
   - Tabs must have `margin-bottom: 0`.
   - Headings inside tab panes need `margin-top: 0` (OPNsense theme applies 18px top margin to h1-h3).
2. **Bootstrap Selectpicker**:
   - OPNsense auto-initializes `.selectpicker` on window load.
   - Instance data key is `selectpicker` (`$el.data('selectpicker')`), NOT `bs.select`.
   - When options change asynchronously, test if initialized before calling refresh.
3. **Monaco Editor + jstree AMD Conflict**:
   - Load `jstree` BEFORE Monaco's `vs/loader.js` (Monaco's AMD loader defines a global `define` which swallows jstree).
   - Set `.vakata-context { z-index: 10000 !important; }` so context menus render above Monaco's canvas.

### Step 9: Packaging & Annotations
1. `config.yml` declares short name (e.g. `name: caddy-advanced`), `pkg-tool` prepends `os-`.
2. `pkg-tool` automatically stages version annotation to `/usr/local/opnsense/version/<short-name>` and generates lifecycle scripts (`post-install`, `post-deinstall` calling `rc.configure_plugins`, `register.php`, and `configctl template reload`).
3. For dynamic dependency reactions, place triggers in `/usr/local/share/pkg/triggers/<name>.ucl`.

---

## 3. Full-Surface Plugin Rename Checklist

Renaming an OPNsense plugin requires updating every layer to avoid silent collision with official `os-*` packages:

- [ ] **Package Identity**: `config.yml` (`name`, `origin: opnware/os-<name>`).
- [ ] **MVC Namespace & Models**: PHP namespace `OPNsense\<Module>`, class names, model XML files, and model mount `<mount>//OPNsense/<module></mount>`.
- [ ] **Controller Bindings**: `$internalModelClass`, `$internalServiceClass`, `$internalServiceTemplate`.
- [ ] **Form IDs**: Dotted IDs in `forms/*.xml` (`<module>.<section>.<field>`).
- [ ] **Configd Namespace**: `actions.d/actions_<ns>.conf` and all `configdRun('<ns> ...')` / `pluginctl -s <ns>` calls.
- [ ] **Plugin Hooks**: `plugins.inc.d/<ns>.inc` and functions `<ns>_services()`, `<ns>_configure()`, `<ns>_syslog()`.
- [ ] **Syslog Facility & Log Module**: PROGRAM rewrite value and destination log directory `/var/log/<ns>/`.
- [ ] **Menu & ACL**: `Menu.xml` tags and `ACL.xml` URL patterns.
- [ ] **State Dirs**: `/var/db/os-<name>` and `/var/run/os-<name>`.
- [ ] **Pkg Triggers**: `usr/local/share/pkg/triggers/os-<name>-*.ucl`.

---

## 4. Hardware & VM Debugging Invariants

- **tcsh Quirk**: The OPNsense VM default shell is `tcsh`. Backgrounding (`&`), `2>/dev/null`, and complex nested quotes in `ssh '...'` fail with `Ambiguous output redirect`. Write a shell script locally, `scp` it to `/tmp/`, and execute with `sh /tmp/script.sh`.
- **Corrupt pkg Database**: If interrupted, fix with:
  `sudo rm -f /var/db/pkg/repos/opnware/db /var/db/pkg/repos/opnware/db-journal && pkg update -f`.
- **API Authentication**: `curl -u` returns 401 because OPNsense requires session cookies and CSRF tokens. Always verify WebUI and API endpoints with Playwright using form login.
- **Diagnostics Severity Filter**: Diagnostics viewer defaults to `Warning` severity. Daemon informational logs require switching the UI severity filter to `Informational`.
