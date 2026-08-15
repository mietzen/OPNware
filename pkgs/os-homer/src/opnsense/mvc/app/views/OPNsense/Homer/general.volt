{#
 # OPNware os-homer — General Settings
 #
 # The generated Caddyfile is intentionally never shown or editable here:
 # it is plugin-owned and regenerated from the settings on every apply.
 #}

<script>
    $(document).ready(function() {
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
            const port = $("#frm_general input[name='homer.general.Port']").val() || "9443";
            const tls = $("#frm_general input[name='homer.general.TlsEnabled']").is(":checked");
            const interfaceValue = $("#frm_general select[name='homer.general.Interface']").val() || "all";
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
    <p class="text-muted">
        {{ lang._('The dashboard is served from the plugin-owned Caddyfile at /usr/local/etc/os-homer/Caddyfile. The Caddyfile is generated from the settings above and is not editable from the WebUI.') }}
    </p>
</div>

<ul id="generalTabsHeader" class="nav nav-tabs opnware-editor-tabs" role="tablist">
    {{ partial("layout_partials/base_tabs_header", ['formData': generalForm]) }}
</ul>

<div id="generalTabsContent" class="content-box tab-content opnware-editor-pane">
    {{ partial("layout_partials/base_tabs_content", ['formData': generalForm]) }}
</div>
