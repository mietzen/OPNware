{#
 # OPNware os-homer — General Settings
 #
 # The generated Caddyfile is intentionally never shown or editable here:
 # it is plugin-owned and regenerated from the settings on every apply.
 #}

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

        $form.on('input change', 'input, select', updateEffectiveUrl);

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
                            // The URL depends only on the just-saved settings;
                            // refresh it now, no page reload needed. (The core
                            // SimpleActionButton has no onActionDone callback —
                            // this is the one reliable post-save hook.)
                            updateEffectiveUrl();
                            updateStatus();
                        },
                        // disable_dialog: validation errors surface as the
                        // inline field note only, no BootstrapDialog popup.
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
            $.getJSON("/api/homer/service/status", function (data) {
                const $status = $("#tbl_homer_status");
                if (!$status.length) {
                    return;
                }
                const running = data.status === "running";
                const badge = running
                    ? '<span class="label label-success">{{ lang._("running") }}</span>'
                    : '<span class="label label-default">{{ lang._("stopped") }}</span>';
                $status.find("#status-running").html(badge);
            });
        }

        function updateEffectiveUrl() {
            const port = fieldVal("homer.general.Port", "9443");
            const tls = $form.find("#homer\\.general\\.TlsEnabled").is(":checked");
            const interfaceValue = $form.find("#homer\\.general\\.Interface").val() || "all";
            const servername = ($form.find("#homer\\.general\\.ServerName").val() || "").trim();
            let host;
            if (servername !== "") {
                // A configured server name is the canonical address (used for
                // the TLS certificate); the interface choice only binds the
                // listener.
                host = servername;
            } else if (interfaceValue === "localhost") {
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
            $("#effective-url").attr("href", url).text(url);
            $("#status-port").text(port);
            $("#status-tls").html(tls ? '<span class="label label-success">{{ lang._("Enabled (HTTPS)") }}</span>' : '<span class="label label-default">{{ lang._("Disabled (HTTP)") }}</span>');
            const intfMap = {
                "localhost": "{{ lang._('Localhost (127.0.0.1)') }}",
                "lan": "{{ lang._('LAN') }}",
                "wan": "{{ lang._('WAN') }}"
            };
            const intfText = intfMap[interfaceValue] || "{{ lang._('All Interfaces') }}";
            $("#status-interface").text(intfText);
        }
    });
</script>

<!-- Live Homer Status Card -->
<div class="content-box" style="margin-bottom: 20px;">
    <div class="table-responsive">
        <table class="table table-striped table-condensed" id="tbl_homer_status">
            <thead>
                <tr>
                    <th colspan="2"><b>{{ lang._('Homer Service Status') }}</b></th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td style="width: 250px;">{{ lang._('Service Status') }}</td>
                    <td id="status-running"><i class="fa fa-spinner fa-pulse"></i></td>
                </tr>
                <tr>
                    <td>{{ lang._('Dashboard URL') }}</td>
                    <td id="status-url"><a id="effective-url" href="{{ effectiveUrl }}" target="_blank" rel="noreferrer">{{ effectiveUrl }}</a></td>
                </tr>
                <tr>
                    <td>{{ lang._('Listen Port') }}</td>
                    <td id="status-port">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('TLS Encryption') }}</td>
                    <td id="status-tls">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('Bind Interface') }}</td>
                    <td id="status-interface">--</td>
                </tr>
            </tbody>
        </table>
    </div>
</div>

<div class="content-box">
    {{ partial("layout_partials/base_form", ['fields': generalForm, 'id': 'frm_general-settings']) }}
    <div class="col-md-12">
        <hr/>
        <button class="btn btn-primary" id="save_general-settings" type="button">
            <b>{{ lang._('Apply') }}</b> <i id="btn_save_progress"></i>
        </button>
        <br/><br/>
    </div>
</div>

<p class="help-block" style="margin-top: 15px;">
    {{ lang._('The dashboard is served from the plugin-owned Caddyfile at /usr/local/etc/os-homer/Caddyfile. The Caddyfile is generated from the settings above and is not editable from the WebUI.') }}
</p>
