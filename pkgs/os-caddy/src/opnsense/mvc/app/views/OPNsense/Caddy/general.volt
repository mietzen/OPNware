{#
 # OPNware os-caddy — General Settings
 #}
<style>
    .content-box.opnware-editor-pane { padding: 15px; }
    .opnware-editor-tabs { margin-bottom: 0; }
    .opnware-tab-pane { padding: 0 15px 15px; }
</style>


<script>
    $(document).ready(function() {
        mapDataToFormUI({'frm_general': "/api/caddy/general/get"}).done(function() {
            $('.selectpicker').selectpicker('refresh');
            updateServiceControlUI('caddy');
            updateStatus();
        });

        $('[id^="save_general-"]').each(function () {
            const $btn = $(this);
            const formId = this.id.replace(/^save_/, 'frm_');

            $btn.attr({
                'data-label'    : "{{ lang._('Apply') }}",
                'data-endpoint' : "/api/caddy/service/reconfigure",
                'data-service-widget' : "caddy"
            });

            $btn.SimpleActionButton({
                onPreAction: function () {
                    const dfObj = new $.Deferred();

                    saveFormToEndpoint(
                        "/api/caddy/general/set",
                        formId,
                        function () {
                            dfObj.resolve();
                        },
                        true,
                        function () {
                            dfObj.reject();
                        }
                    );
                    return dfObj.promise();
                }
            });
        });

        function updateStatus() {
            $.getJSON("/api/caddy/status", function (data) {
                const $status = $("#caddy-status");
                if (!$status.length) {
                    return;
                }
                const running = data.running ? "{{ lang._('running') }}" : "{{ lang._('stopped') }}";
                $status.find("#status-running").html("<strong>" + running + "</strong>");
                $status.find("#status-version").text(data.version || "-");
                $status.find("#status-config").text(data.config_path || "-");
                $status.find("#status-modules").text((data.modules || []).join(", ") || "-");
                $status.find("#status-checksum").text(data.checksum || "-");
                $status.find("#status-validate").text(data.validate || "-");
            });
        }
    });
</script>

<div id="caddy-status" class="content-box opnware-editor-pane __mb">
    <h2>{{ lang._('Status') }}</h2>
    <table class="table table-striped table-condensed">
        <tbody>
            <tr><td class="text-muted" style="width: 220px;">{{ lang._('Service') }}</td><td id="status-running"></td></tr>
            <tr><td class="text-muted">{{ lang._('Version') }}</td><td id="status-version"></td></tr>
            <tr><td class="text-muted">{{ lang._('Config path') }}</td><td id="status-config"></td></tr>
            <tr><td class="text-muted">{{ lang._('Modules') }}</td><td id="status-modules"></td></tr>
            <tr><td class="text-muted">{{ lang._('Config checksum') }}</td><td id="status-checksum"></td></tr>
            <tr><td class="text-muted">{{ lang._('Config validation') }}</td><td id="status-validate"></td></tr>
        </tbody>
    </table>
</div>

<ul id="generalTabsHeader" class="nav nav-tabs opnware-editor-tabs" role="tablist">
    {{ partial("layout_partials/base_tabs_header", ['formData': generalForm]) }}
</ul>

<div id="generalTabsContent" class="content-box tab-content opnware-tab-pane">
    {{ partial("layout_partials/base_tabs_content", ['formData': generalForm]) }}
</div>
