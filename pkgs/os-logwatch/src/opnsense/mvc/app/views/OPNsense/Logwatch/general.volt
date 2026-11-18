{#
 # Copyright (C) 2026 Nils Stein
 # All rights reserved.
 #
 # OPNware os-logwatch — Settings
 #}
<script>
    $(document).ready(function () {
        window.scrollTo(0, 0);

        function refreshSmtpHints() {
            const useMonit = $('#logwatch\\.general\\.use_monit_smtp').is(':checked');
            $('#ly-monit-banner').toggle(useMonit);
        }

        function updateStatus() {
            $.getJSON('/api/logwatch/service/status', function (svc) {
                const running = svc && svc.status === 'running';
                const badge = running
                    ? '<span class="label label-success">{{ lang._("running") }}</span>'
                    : '<span class="label label-default">{{ lang._("stopped") }}</span>';
                $('#ly-status-running').html(badge);
            });
            $.getJSON('/api/logwatch/logs/stats', function (st) {
                if (st && st.status === 'ok') {
                    $('#ly-status-db').text((st.total_rows || 0) + ' {{ lang._("rows") }} (' + (st.db_size_mb || 0) + ' MB)');
                    $('#ly-status-24h').text((st.errors_24h || 0) + ' {{ lang._("errors") }}, ' + (st.warnings_24h || 0) + ' {{ lang._("warnings") }}');
                }
            });
        }

        mapDataToFormUI({'frm_general': '/api/logwatch/general/get'}).done(function () {
            formatTokenizersUI();
            $('.selectpicker').each(function () {
                if ($(this).data('selectpicker')) {
                    $(this).selectpicker('refresh');
                }
            });
            refreshSmtpHints();
            updateServiceControlUI('logwatch');
            updateStatus();
            window.scrollTo(0, 0);
        });

        $('#frm_general-settings').on('change', '#logwatch\\.general\\.use_monit_smtp', refreshSmtpHints);

        $('#btn_save').attr({
            'data-label': "{{ lang._('Apply') }}",
            'data-endpoint': '/api/logwatch/service/reconfigure',
            'data-service-widget': 'logwatch'
        }).SimpleActionButton({
            onPreAction: function () {
                const dfObj = new $.Deferred();
                saveFormToEndpoint(
                    '/api/logwatch/general/set',
                    'frm_general-settings',
                    function () {
                        dfObj.resolve();
                        setTimeout(updateStatus, 600);
                    },
                    true,
                    function () {
                        dfObj.reject();
                    }
                );
                return dfObj.promise();
            }
        });

        $('#btn-test-smtp').on('click', function () {
            const $btn = $(this).prop('disabled', true);
            const $msg = $('#smtp-test-result').text('{{ lang._("Sending test email...") }}').removeClass('text-success text-danger');
            $.post('/api/logwatch/general/testSmtp', {
                use_monit_smtp: $('#logwatch\\.general\\.use_monit_smtp').is(':checked') ? '1' : '0',
                smtp_host: $('#logwatch\\.general\\.smtp_host').val() || '',
                smtp_port: $('#logwatch\\.general\\.smtp_port').val() || '587',
                smtp_user: $('#logwatch\\.general\\.smtp_user').val() || '',
                smtp_password: $('#logwatch\\.general\\.smtp_password').val() || '',
                smtp_from: $('#logwatch\\.general\\.smtp_from').val() || '',
                smtp_to: $('#logwatch\\.general\\.smtp_to').val() || ''
            }, function (res) {
                $btn.prop('disabled', false);
                if (res && res.status === 'ok') {
                    $msg.addClass('text-success').text(res.message);
                } else {
                    $msg.addClass('text-danger').text((res && res.message) || '{{ lang._("Test email failed") }}');
                }
            }).fail(function () {
                $btn.prop('disabled', false);
                $msg.addClass('text-danger').text('{{ lang._("Request failed") }}');
            });
        });
    });
</script>

<!-- Live Status Card -->
<div class="content-box" style="margin-bottom: 20px;">
    <div class="table-responsive">
        <table class="table table-striped table-condensed">
            <thead>
                <tr><th colspan="2"><b>{{ lang._('Logwatch Service Status') }}</b></th></tr>
            </thead>
            <tbody>
                <tr><td style="width: 250px;">{{ lang._('Service Status') }}</td><td id="ly-status-running"><i class="fa fa-spinner fa-pulse"></i></td></tr>
                <tr><td>{{ lang._('Ingest Socket') }}</td><td><code>/var/run/os-logwatch/ingest.sock</code></td></tr>
                <tr><td>{{ lang._('SQLite Database') }}</td><td id="ly-status-db">--</td></tr>
                <tr><td>{{ lang._('Last 24h Events') }}</td><td id="ly-status-24h">--</td></tr>
            </tbody>
        </table>
    </div>
</div>

{% if monitSummary['configured'] %}
<div class="alert alert-info" id="ly-monit-banner" style="margin-bottom: 15px;">
    <i class="fa fa-envelope-o"></i>
    <b>{{ lang._('Monit SMTP Detected') }}:</b>
    <code>{{ monitSummary['host'] }}:{{ monitSummary['port'] }}</code>
    {% if monitSummary['to'] != '' %} &rarr; <code>{{ monitSummary['to'] }}</code>{% endif %}
    ({{ lang._('Leave custom SMTP fields blank below to reuse these settings automatically.') }})
</div>
{% else %}
<div class="alert alert-warning" id="ly-monit-banner" style="margin-bottom: 15px;">
    <i class="fa fa-exclamation-triangle"></i>
    {{ lang._('No remote SMTP server detected in Services -> Monit. Configure custom SMTP fields below or set up Monit first.') }}
</div>
{% endif %}

<div class="content-box">
    {{ partial("layout_partials/base_form", ['fields': generalForm, 'id': 'frm_general-settings']) }}
    <div class="col-md-12">
        <hr/>
        <button class="btn btn-primary" id="btn_save" type="button"><b>{{ lang._('Apply') }}</b></button>
        <button class="btn btn-default" id="btn-test-smtp" type="button" style="margin-left: 8px;"><i class="fa fa-paper-plane"></i> {{ lang._('Send Test Email') }}</button>
        <span id="smtp-test-result" style="margin-left: 10px; font-weight: bold;"></span>
        <br/><br/>
    </div>
</div>
