{#
 # OPNware os-caddy-advanced — General Settings
 #}
<style>
    .opnware-editor-tabs { margin-bottom: 0; }
    .opnware-tab-pane { padding: 0 15px 15px; }
</style>

<script>
    $(document).ready(function() {
        window.scrollTo(0, 0);
        mapDataToFormUI({'frm_general': "/api/caddyadvanced/general/get"}).done(function() {
            $('.selectpicker').selectpicker('refresh');
            updateServiceControlUI('caddyadvanced');
            updateStatus();
            window.scrollTo(0, 0);
        });

        $('[id^="save_general-"]').each(function () {
            const $btn = $(this);
            const formId = this.id.replace(/^save_/, 'frm_');

            $btn.attr({
                'data-label'    : "{{ lang._('Apply') }}",
                'data-endpoint' : "/api/caddyadvanced/service/reconfigure",
                'data-service-widget' : "caddyadvanced"
            });

            $btn.SimpleActionButton({
                onPreAction: function () {
                    const dfObj = new $.Deferred();

                    saveFormToEndpoint(
                        "/api/caddyadvanced/general/set",
                        formId,
                        function () {
                            dfObj.resolve();
                            updateStatus();
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
            $.getJSON("/api/caddyadvanced/status", function (data) {
                const $status = $("#tbl_caddy_status");
                if (!$status.length) {
                    return;
                }
                const running = data.running
                    ? '<span class="label label-success">{{ lang._("running") }}</span>'
                    : '<span class="label label-default">{{ lang._("stopped") }}</span>';
                $status.find("#status-running").html(running);
                $status.find("#status-version").text(data.version || "--");
                $status.find("#status-modules").text((data.modules && data.modules.length > 0) ? data.modules.join(", ") : "{{ lang._('Standard distribution') }}");

                let valHtml = '--';
                if (data.validate === 'OK') {
                    valHtml = '<span class="label label-success">{{ lang._("OK") }}</span>';
                } else if (data.validate) {
                    valHtml = '<span class="label label-danger">' + $('<div>').text(data.validate).html() + '</span>';
                }
                $status.find("#status-validate").html(valHtml);
            });
        }
    });
</script>

<!-- Live Caddy Status Card -->
<div class="content-box" style="margin-bottom: 20px;">
    <div class="table-responsive">
        <table class="table table-striped table-condensed" id="tbl_caddy_status">
            <thead>
                <tr>
                    <th colspan="2"><b>{{ lang._('Caddy Service Status') }}</b></th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td style="width: 250px;">{{ lang._('Service Status') }}</td>
                    <td id="status-running"><i class="fa fa-spinner fa-pulse"></i></td>
                </tr>
                <tr>
                    <td>{{ lang._('Caddy Version') }}</td>
                    <td id="status-version">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('Loaded Plugins') }}</td>
                    <td id="status-modules">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('Configuration State') }}</td>
                    <td id="status-validate">--</td>
                </tr>
            </tbody>
        </table>
    </div>
</div>

<ul id="generalTabsHeader" class="nav nav-tabs opnware-editor-tabs" role="tablist">
    {{ partial("layout_partials/base_tabs_header", ['formData': generalForm]) }}
</ul>

<div id="generalTabsContent" class="content-box tab-content opnware-tab-pane">
    {{ partial("layout_partials/base_tabs_content", ['formData': generalForm]) }}
</div>
