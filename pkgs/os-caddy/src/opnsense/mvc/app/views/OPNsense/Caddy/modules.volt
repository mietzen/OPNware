{#
 # OPNware os-caddy — Module Management
 #
 # Declared modules are rebuilt into the caddy binary via xcaddy, pinned to
 # the installed caddy version. The rebuild is atomic (temp -> verify -> swap);
 # a failed rebuild never replaces the running binary.
 #}

<script>
    $(document).ready(function() {
        mapDataToFormUI({'frm_modules': "/api/caddy/modules/get"}).done(function() {
            $('.selectpicker').selectpicker('refresh');
            updateStatus();
        });

        $("#save_modules").click(function() {
            saveFormToEndpoint(
                "/api/caddy/modules/set",
                "frm_modules",
                function() {
                    updateStatus();
                }
            );
        });

        $("#rebuild_modules").click(function() {
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
    });
</script>

<div id="modules-status" class="content-box __mb" style="padding-bottom: 1.5em;">
    <div class="content-box-main">
        <h2>{{ lang._('Module status') }}</h2>
        <table class="table table-striped table-condensed">
            <tbody>
                <tr><td class="text-muted">{{ lang._('Installed modules') }}</td><td id="status-modules"></td></tr>
                <tr><td class="text-muted">{{ lang._('Build fingerprint') }}</td><td id="status-fingerprint"></td></tr>
                <tr><td class="text-muted">{{ lang._('Last result') }}</td><td id="status-last-ok"></td></tr>
                <tr><td class="text-muted">{{ lang._('Last run') }}</td><td id="status-last-ts"></td></tr>
                <tr><td class="text-muted">{{ lang._('Last message') }}</td><td id="status-last-message"></td></tr>
            </tbody>
        </table>
    </div>
</div>

<div id="modules-result" class="alert" style="display:none;"></div>

<form id="frm_modules" class="form-horizontal">
    <div class="content-box __mb" style="padding-bottom: 1.5em;">
        <div class="content-box-main">
            <h2>{{ lang._('Declared modules') }}</h2>
            <div class="form-group">
                <label class="col-sm-2 control-label" for="caddy.general.Modules">{{ lang._('Modules') }}</label>
                <div class="col-sm-10">
                    <textarea id="caddy.general.Modules" class="form-control" rows="8"
                              placeholder="github.com/caddy-dns/cloudflare"></textarea>
                    <span class="help-block">{{ lang._('Add one Go module path per line. Save the list, then use Install / Rebuild to compile a caddy binary pinned to the installed version. A failed rebuild never replaces the running binary.') }}</span>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-12">
        <hr/>
        <button id="save_modules" type="button" class="btn btn-primary"><b>{{ lang._('Save') }}</b></button>
        <button id="rebuild_modules" type="button" class="btn btn-warning __ml"><b>{{ lang._('Install / Rebuild') }}</b></button>
        <button id="ensure_modules" type="button" class="btn btn-info __ml"><b>{{ lang._('Check') }}</b></button>
    </div>
</form>
