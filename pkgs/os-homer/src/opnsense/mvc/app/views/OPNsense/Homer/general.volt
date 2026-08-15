{#
 # OPNware os-homer — General Settings
 #
 # The generated Caddyfile is intentionally never shown or editable here:
 # it is plugin-owned and regenerated from the settings on every apply.
 #}
<style>
    .content-box.opnware-editor-pane { padding: 15px; }
    .content-box.opnware-editor-pane h2 { margin-top: 0; }
    .opnware-editor-tabs { margin-bottom: 0; }
    .opnware-tab-pane { padding: 0 15px 15px; }
</style>


<script>
    $(document).ready(function() {
        // OPNsense MVC form fields carry dotted ids (homer.general.Port) and
        // no name attribute; the form itself is frm_<tab-id>.
        const $form = $("#frm_general-settings");

        function fieldVal(id, fallback) {
            const v = $form.find("#" + id.replace(/\./g, '\\.')).val();
            return v !== undefined && v !== '' ? v : fallback;
        }

        mapDataToFormUI({'frm_general': "/api/homer/general/get"}).done(function() {
            $('.selectpicker').selectpicker('refresh');
            updateServiceControlUI('homer');
            updateStatus();
            updateEffectiveUrl();
        });

        $('[id^="save_general-"]').each(function () {
            const $btn = $(this);
            const formId = this.id.replace(/^save_/, 'frm_');

            $btn.attr({
                'data-label'    : "{{ lang._('Apply') }}",
                'data-endpoint' : "/api/homer/service/reconfigure",
                'data-service-widget' : "homer"
            });

            $btn.SimpleActionButton({
                onPreAction: function () {
                    const dfObj = new $.Deferred();

                    saveFormToEndpoint(
                        "/api/homer/general/set",
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
                },
                onActionDone: function () {
                    updateEffectiveUrl();
                }
            });
        });

        function updateStatus() {
            $.getJSON("/api/homer/service/status", function (data) {
                const $status = $("#homer-status");
                if (!$status.length) {
                    return;
                }
                const running = data.status === "running";
                $status.find("#status-running").html("<strong>" + (running ? "{{ lang._('running') }}" : "{{ lang._('stopped') }}") + "</strong>");
            });
        }

        function updateEffectiveUrl() {
            const port = fieldVal("homer.general.Port", "9443");
            const tls = $form.find("#homer\\.general\\.TlsEnabled").is(":checked");
            const interfaceValue = $form.find("#homer\\.general\\.Interface").val() || "all";
            let host;
            if (interfaceValue === "localhost") {
                host = "127.0.0.1";
            } else if (interfaceValue === "lan") {
                host = "{{ lanIp }}";
            } else {
                host = "{{ requestHost }}";
            }
            if (host.indexOf(":") !== -1) {
                host = "[" + host + "]";
            }
            const scheme = tls ? "https" : "http";
            const url = scheme + "://" + host + ":" + port + "/";
            $("#effective-url").attr("href", url);
            $("#effective-url").text(url);
        }
    });
</script>

<div id="homer-status" class="content-box opnware-editor-pane __mb">
    <h2>{{ lang._('Status') }}</h2>
    <table class="table table-striped table-condensed">
        <tbody>
            <tr><td class="text-muted" style="width: 220px;">{{ lang._('Service') }}</td><td id="status-running"></td></tr>
            <tr><td class="text-muted">{{ lang._('Effective URL') }}</td><td><a id="effective-url" href="{{ effectiveUrl }}" target="_blank" rel="noreferrer">{{ effectiveUrl }}</a></td></tr>
        </tbody>
    </table>
</div>

<ul id="generalTabsHeader" class="nav nav-tabs opnware-editor-tabs" role="tablist">
    {{ partial("layout_partials/base_tabs_header", ['formData': generalForm]) }}
</ul>

<div id="generalTabsContent" class="content-box tab-content opnware-tab-pane">
    {{ partial("layout_partials/base_tabs_content", ['formData': generalForm]) }}
</div>

<p class="help-block">
    {{ lang._('The dashboard is served from the plugin-owned Caddyfile at /usr/local/etc/os-homer/Caddyfile. The Caddyfile is generated from the settings above and is not editable from the WebUI.') }}
</p>
