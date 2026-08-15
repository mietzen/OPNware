{#
 # OPNware os-caddy — Module Management
 #
 # Declared modules are rebuilt into the caddy binary via xcaddy, pinned to
 # the installed caddy version. The rebuild is atomic (temp -> verify -> swap);
 # a failed rebuild never replaces the running binary.
 #}
<style>
    .content-box.opnware-editor-pane { padding: 15px; }
    .content-box.opnware-editor-pane h2 { margin-top: 0; }
    .opnware-editor-actions { padding: 0 15px 15px; }
    .opnware-editor-tabs { margin-bottom: 0; }
    .form-inline .bootstrap-select { max-width: 420px; }
</style>


<script>
    $(document).ready(function() {
        let modules = [];
        let catalog = [];

        function updateStatus() {
            $.getJSON("/api/caddy/modules/status", function(data) {
                const $status = $("#modules-status");
                if (!$status.length) {
                    return;
                }
                $status.find("#status-modules").text((data.modules || []).join(", ") || "-");
                $status.find("#status-fingerprint").text(data.fingerprint || "-");
                const last = data.last_result || {};
                $status.find("#status-last-ok").text(last.ok === true ? "{{ lang._('OK') }}" : (last.ok === false ? "{{ lang._('FAILED') }}" : "-"));
                $status.find("#status-last-ts").text(last.ts ? new Date(last.ts * 1000).toLocaleString() : "-");
                $status.find("#status-last-message").text(last.message || "-");
            });
        }

        function renderModuleSelect() {
            const $select = $("#module-catalog");
            const selected = $select.val() || "";
            $select.empty();
            catalog.forEach(function(pkg) {
                if (modules.indexOf(pkg) === -1) {
                    $select.append($('<option>').val(pkg).text(pkg));
                }
            });
            if (selected && catalog.indexOf(selected) !== -1 && modules.indexOf(selected) === -1) {
                $select.val(selected);
            } else {
                $select.val('');
            }
            // bootstrap-select auto-initializes on window load; if the catalog
            // fetch wins the race, initialize here instead of refreshing a
            // plugin that isn't mounted yet.
            if ($select.data('selectpicker')) {
                $select.selectpicker('refresh');
            } else {
                $select.selectpicker();
            }
        }

        function renderModules() {
            const $tbody = $("#modules-table tbody");
            $tbody.empty();
            modules.forEach(function(mod, index) {
                const $tr = $('<tr>');
                $tr.append($('<td>').text(mod));
                $tr.append($('<td class="text-right">').append(
                    $('<button type="button" class="btn btn-danger btn-xs">').text("{{ lang._('Remove') }}")
                        .click(function() {
                            modules.splice(index, 1);
                            renderModules();
                        })
                ));
                $tbody.append($tr);
            });
            if (!modules.length) {
                $tbody.append(
                    $('<tr><td colspan="2" class="text-muted">{{ lang._('No modules declared.') }}</td></tr>')
                );
            }
            renderModuleSelect();
        }

        function loadCatalog() {
            $.getJSON("/api/caddy/modules/catalog", function(data) {
                if (data.status !== "ok" || !Array.isArray(data.modules)) {
                    $("#catalog-note").text(data.message || "{{ lang._('Could not load the module catalog.') }}").show();
                    return;
                }
                catalog = data.modules;
                $("#catalog-note").hide();
                renderModuleSelect();
            });
        }

        function loadModules() {
            $.getJSON("/api/caddy/modules/get", function(data) {
                if (!data || !data.caddy || !data.caddy.general) {
                    showResult({ok: false, message: "{{ lang._('Could not load declared modules.') }}"});
                    return;
                }
                modules = String(data.caddy.general.Modules || '')
                    .split("\n").map(function(s) { return s.trim(); })
                    .filter(function(s) { return s !== ''; });
                renderModules();
            });
        }

        function saveModules() {
            $("#modules-result").hide();
            const joined = modules.join("\n");
            $.post("/api/caddy/modules/set", {
                caddy: { general: { Modules: joined } }
            }, function(data) {
                if (data.status === "ok" || data.result === "saved" || data.result === "ok") {
                    showResult({ok: true, message: "{{ lang._('Declared modules saved.') }}"});
                } else {
                    showResult({ok: false, message: (data.message || JSON.stringify(data))});
                }
            });
        }

        $("#add-module").click(function() {
            const value = $("#module-catalog").val() || "";
            if (!value) {
                return;
            }
            $("#module-catalog").val('');
            if ($("#module-catalog").data('selectpicker')) {
                $("#module-catalog").selectpicker('refresh');
            }
            modules.push(value);
            renderModules();
        });

        $("#add-custom-module").click(function() {
            const value = $("#new-module").val().trim();
            if (!value) {
                return;
            }
            $("#new-module").val('');
            modules.push(value);
            renderModules();
        });

        $("#new-module").keydown(function(e) {
            if (e.which === 13) {
                e.preventDefault();
                $("#add-custom-module").click();
            }
        });

        $("#save_modules").click(saveModules);

        $("#rebuild_modules").click(function() {
            saveModules();
            $("#modules-result").hide();
            $.post("/api/caddy/modules/rebuild", function(data) {
                showResult(data);
                updateStatus();
            });
        });

        $("#ensure_modules").click(function() {
            $("#modules-result").hide();
            $.post("/api/caddy/modules/ensure", function(data) {
                showResult(data);
                updateStatus();
            });
        });

        function showResult(data) {
            const $box = $("#modules-result");
            if (data.ok) {
                $box.removeClass("alert-danger").addClass("alert-success");
            } else {
                $box.removeClass("alert-success").addClass("alert-danger");
            }
            $box.text(data.message || JSON.stringify(data));
            $box.show();
        }

        loadCatalog();
        loadModules();
        updateStatus();
    });
</script>

<div id="modules-status" class="content-box opnware-editor-pane __mb">
    <h2>{{ lang._('Module status') }}</h2>
    <table class="table table-striped table-condensed">
        <tbody>
            <tr><td class="text-muted" style="width: 220px;">{{ lang._('Installed modules') }}</td><td id="status-modules"></td></tr>
            <tr><td class="text-muted">{{ lang._('Build fingerprint') }}</td><td id="status-fingerprint"></td></tr>
            <tr><td class="text-muted">{{ lang._('Last result') }}</td><td id="status-last-ok"></td></tr>
            <tr><td class="text-muted">{{ lang._('Last run') }}</td><td id="status-last-ts"></td></tr>
            <tr><td class="text-muted">{{ lang._('Last message') }}</td><td id="status-last-message"></td></tr>
        </tbody>
    </table>
</div>

<div id="modules-result" class="alert" style="display:none;"></div>

<div class="content-box opnware-editor-pane __mb">
    <h2>{{ lang._('Declared modules') }}</h2>
    <p class="help-block">
        {{ lang._('Pick a module from the official Caddy module catalog, or paste any Go module path below. Save the list, then Install / Rebuild compiles a caddy binary pinned to the installed version. A failed rebuild never replaces the running binary.') }}
    </p>
    <table class="table table-striped table-condensed" id="modules-table">
        <thead>
            <tr>
                <th>{{ lang._('Module') }}</th>
                <th class="text-right" style="width: 90px;"></th>
            </tr>
        </thead>
        <tbody></tbody>
    </table>
    <div class="form-inline __mt">
        <select id="module-catalog" class="selectpicker" data-live-search="true" data-container="body"
                data-width="auto" title="{{ lang._('Select a module…') }}"></select>
        <button id="add-module" type="button" class="btn btn-primary btn-sm">{{ lang._('Add') }}</button>
        <span id="catalog-note" class="help-block" style="display:none;"></span>
    </div>
    <div class="form-inline __mt">
        <input id="new-module" type="text" class="form-control input-sm" style="width: 420px; max-width: 100%;"
               placeholder="{{ lang._('custom Go module path, e.g. github.com/me/my-caddy-module') }}">
        <button id="add-custom-module" type="button" class="btn btn-default btn-sm">{{ lang._('Add custom') }}</button>
    </div>
</div>

<div class="opnware-editor-actions">
    <button id="save_modules" type="button" class="btn btn-primary"><b>{{ lang._('Save') }}</b></button>
    <button id="rebuild_modules" type="button" class="btn btn-warning __ml"><b>{{ lang._('Install / Rebuild') }}</b></button>
    <button id="ensure_modules" type="button" class="btn btn-info __ml"><b>{{ lang._('Check') }}</b></button>
</div>
