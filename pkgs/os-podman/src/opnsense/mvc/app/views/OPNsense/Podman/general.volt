{#
 # Copyright (C) 2026 Nils Stein
 # All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions are met:
 #
 # 1. Redistributions of source code must retain the above copyright notice,
 #    this list of conditions and the following disclaimer.
 #
 # 2. Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #
 # THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 # INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 # AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 # AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 # OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 # SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 # INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 # CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 # ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 # POSSIBILITY OF SUCH DAMAGE.
 #}

<script>
    function updateStatus() {
        ajaxGet('/api/podman/system/status', {}, function (data, status) {
            if (data) {
                var running = data.running ? '<span class="label label-success">{{ lang._("running") }}</span>' : '<span class="label label-default">{{ lang._("stopped") }}</span>';
                $('#status-running').html(running);
                $('#status-version').text(data.version || '--');
                $('#status-storage').text(data.storage || '--');
                $('#status-linux').text(data.linux_emulation || '--');
                $('#status-tcp').text(data.tcp_endpoint || '--');
                $('#status-interfaces').text(data.interfaces ? data.interfaces.toUpperCase() : 'LAN');
            }
        });
    }

    $(document).ready(function () {
        var data_get_map = {'frm_general': '/api/podman/general/get'};
        mapDataToFormUI(data_get_map).done(function (data) {
            formatTokenizersUI();
            $('.selectpicker').each(function () {
                if ($(this).data('selectpicker')) {
                    $(this).selectpicker('refresh');
                }
            });
            updateServiceControlUI('podman');
            updateStatus();
        });

        $('#btn_save').click(function () {
            $('#btn_save_progress').addClass('fa fa-spinner fa-pulse');
            $('#btn_save').prop('disabled', true);
            saveFormToEndpoint('/api/podman/general/set', 'frm_general-settings', function () {
                ajaxCall('/api/podman/service/reconfigure', {}, function (data, status) {
                    $('#btn_save_progress').removeClass('fa fa-spinner fa-pulse');
                    $('#btn_save').prop('disabled', false);
                    updateServiceControlUI('podman');
                    updateStatus();
                });
            }, false, function () {
                $('#btn_save_progress').removeClass('fa fa-spinner fa-pulse');
                $('#btn_save').prop('disabled', false);
            });
        });
    });
</script>

<!-- Live Podman Status Card -->
<div class="content-box" style="margin-bottom: 20px;">
    <div class="table-responsive">
        <table class="table table-striped table-condensed" id="tbl_podman_status">
            <thead>
                <tr>
                    <th colspan="2"><b>{{ lang._('Podman Service & Storage Status') }}</b></th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td style="width: 250px;">{{ lang._('Service Status') }}</td>
                    <td id="status-running"><i class="fa fa-spinner fa-pulse"></i></td>
                </tr>
                <tr>
                    <td>{{ lang._('Podman Version') }}</td>
                    <td id="status-version">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('UNIX Socket') }}</td>
                    <td><code>/var/run/podman/podman.sock</code></td>
                </tr>
                <tr>
                    <td>{{ lang._('Storage Driver') }}</td>
                    <td id="status-storage">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('Linux Emulation') }}</td>
                    <td id="status-linux">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('TCP REST Endpoint') }}</td>
                    <td id="status-tcp">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('Firewall Interfaces') }}</td>
                    <td id="status-interfaces">--</td>
                </tr>
            </tbody>
        </table>
    </div>
</div>

<div class="content-box">
    {{ partial("layout_partials/base_form", ['fields': generalForm, 'id': 'frm_general-settings']) }}
    <div class="col-md-12">
        <hr/>
        <button class="btn btn-primary" id="btn_save" type="button">
            <b>{{ lang._('Apply') }}</b> <i id="btn_save_progress"></i>
        </button>
        <br/><br/>
    </div>
</div>
