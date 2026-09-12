{#
 # Copyright (C) 2026 Nils Mietzen
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
    function updateRemoteGuide(data) {
        var lanIp = data.lan_ip || '{{ lanIp }}';
        var sshActive = !!data.ssh_enabled;
        var sshHost = 'ssh://root@' + lanIp;

        $('#snippet-ssh-docker').text('docker context create opnsense-docker --docker "host=' + sshHost + '"\ndocker context use opnsense-docker');
        $('#snippet-docker-env').text('export DOCKER_HOST="' + sshHost + '"');

        if (!sshActive) {
            $('#guide-warning-box').show();
            $('#guide-content-box').hide();
        } else {
            $('#guide-warning-box').hide();
            $('#guide-content-box').show();
        }
    }

    function copySnippet(elemId, btnElem) {
        var text = $('#' + elemId).text();
        if (navigator.clipboard) {
            navigator.clipboard.writeText(text).then(function() {
                var $icon = $(btnElem).find('i');
                $icon.removeClass('fa-clipboard').addClass('fa-check text-success');
                setTimeout(function() {
                    $icon.removeClass('fa-check text-success').addClass('fa-clipboard');
                }, 2000);
            });
        }
    }

    function updateStatus() {
        ajaxGet('/api/docker/system/status', {}, function (data, status) {
            if (data) {
                var running = data.running ? '<span class="label label-success">{{ lang._("running") }}</span>' : '<span class="label label-default">{{ lang._("stopped") }}</span>';
                $('#status-running').html(running);
                $('#status-version').text(data.version || '--');
                $('#status-microvm').text(data.microvm || '--');
                $('#status-vm-ip').text(data.ip || '100.64.0.2');
                $('#status-portsync').text(data.port_sync ? 'Active' : 'Disabled');
                $('#status-interfaces').text(data.interfaces ? data.interfaces.toUpperCase() : 'LAN');
                updateRemoteGuide(data);
            }
        });
    }

    $(document).ready(function () {
        window.scrollTo(0, 0);
        var data_get_map = {'frm_general': '/api/docker/general/get'};
        mapDataToFormUI(data_get_map).done(function (data) {
            formatTokenizersUI();
            $('.selectpicker').each(function () {
                if ($(this).data('selectpicker')) {
                    $(this).selectpicker('refresh');
                } else {
                    $(this).selectpicker();
                }
            });
            updateServiceControlUI('docker');
            updateStatus();
            window.scrollTo(0, 0);
        });

        // Dynamic host hardware resource detection and range sliders
        ajaxGet('/api/docker/general/host_resources', {}, function (data, status) {
            if (status === 'success' && data) {
                var cpus = data.cpus || 2;
                var memMb = data.memory_mb || 2048;
                var freeGb = data.disk_free_gb || 50;
                var maxMem = Math.max(512, memMb - 1024);

                var cpuInput = $('#docker\\.general\\.cpus');
                var memInput = $('#docker\\.general\\.memory');
                var diskInput = $('#docker\\.general\\.disk_size');

                if (cpuInput.length > 0 && $('#slider_cpus').length === 0) {
                    cpuInput.after('<input type="range" id="slider_cpus" min="1" max="' + cpus + '" value="' + (cpuInput.val() || 2) + '" style="margin-top:6px;">');
                    $('#slider_cpus').on('input change', function () {
                        cpuInput.val($(this).val());
                    });
                    cpuInput.on('input change', function () {
                        $('#slider_cpus').val($(this).val());
                    });
                }

                if (memInput.length > 0 && $('#slider_mem').length === 0) {
                    memInput.after('<input type="range" id="slider_mem" min="512" max="' + maxMem + '" step="256" value="' + (memInput.val() || 2048) + '" style="margin-top:6px;">');
                    $('#slider_mem').on('input change', function () {
                        memInput.val($(this).val());
                    });
                    memInput.on('input change', function () {
                        $('#slider_mem').val($(this).val());
                    });
                }

                if (diskInput.length > 0 && $('#slider_disk').length === 0) {
                    diskInput.after('<input type="range" id="slider_disk" min="5" max="500" step="5" value="' + (diskInput.val() || 20) + '" style="margin-top:6px;">');
                    $('#slider_disk').on('input change', function () {
                        diskInput.val($(this).val());
                    });
                    diskInput.on('input change', function () {
                        $('#slider_disk').val($(this).val());
                    });
                }

                var cpuHelp = "{{ lang._('Host available CPU cores: ') }}" + cpus + ". " + "{{ lang._('Allocated to microVM (1 - ') }}" + cpus + ").";
                var memHelp = "{{ lang._('Host physical RAM: ') }}" + memMb + " MB. " + "{{ lang._('Allocated to microVM (512 - ') }}" + maxMem + " MB).";
                var diskHelp = "{{ lang._('Storage pool free space: ') }}" + freeGb + " GB. " + "{{ lang._('Allocated sparse data disk for /var/lib/docker.') }}";

                cpuInput.closest('tr').find('small').text(cpuHelp);
                memInput.closest('tr').find('small').text(memHelp);
                diskInput.closest('tr').find('small').text(diskHelp);
            }
        });

        $('#btn_save').click(function () {
            $('#btn_save_progress').addClass('fa fa-spinner fa-pulse');
            $('#btn_save').prop('disabled', true);
            saveFormToEndpoint('/api/docker/general/set', 'frm_general-settings', function () {
                ajaxCall('/api/docker/service/reconfigure', {}, function (data, status) {
                    $('#btn_save_progress').removeClass('fa fa-spinner fa-pulse');
                    $('#btn_save').prop('disabled', false);
                    updateServiceControlUI('docker');
                    updateStatus();
                });
            }, false, function () {
                $('#btn_save_progress').removeClass('fa fa-spinner fa-pulse');
                $('#btn_save').prop('disabled', false);
            });
        });
    });
</script>

<!-- Live Docker Status Card -->
<div class="content-box" style="margin-bottom: 20px;">
    <div class="table-responsive">
        <table class="table table-striped table-condensed" id="tbl_docker_status">
            <thead>
                <tr>
                    <th colspan="2"><b>{{ lang._('Docker Service & MicroVM Status') }}</b></th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td style="width: 250px;">{{ lang._('Service Status') }}</td>
                    <td id="status-running"><i class="fa fa-spinner fa-pulse"></i></td>
                </tr>
                <tr>
                    <td>{{ lang._('Docker CLI Version') }}</td>
                    <td id="status-version">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('Alpine MicroVM') }}</td>
                    <td id="status-microvm">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('MicroVM IPv4 Address') }}</td>
                    <td id="status-vm-ip">100.64.0.2</td>
                </tr>
                <tr>
                    <td>{{ lang._('Dynamic Port Forwarding') }}</td>
                    <td id="status-portsync">--</td>
                </tr>
                <tr>
                    <td>{{ lang._('Firewall Interfaces') }}</td>
                    <td id="status-interfaces">--</td>
                </tr>
            </tbody>
        </table>
    </div>
</div>

<!-- Remote Connection Guide Card -->
<div class="content-box" style="margin-bottom: 20px; padding: 15px;">
    <h4 style="margin-top: 0;"><b>{{ lang._('Remote Client Setup & Connection Guide') }}</b></h4>
    <p class="text-muted">
        {{ lang._('Manage Docker containers, images, volumes, and Compose stacks on this OPNsense firewall directly from your workstation terminal, Docker CLI, VS Code, or Portainer.') }}
    </p>

    <!-- Warning Alert when SSH is disabled -->
    <div id="guide-warning-box" class="alert alert-warning" style="display: none; margin-bottom: 0;">
        <i class="fa fa-exclamation-triangle"></i>
        {{ lang._('Remote container management over SSH is currently unavailable because SSH is disabled on this firewall. Enable SSH in System: Settings: Administration.') }}
    </div>

    <!-- Active Guides Box -->
    <div id="guide-content-box" style="display: none;">
        <p><b>{{ lang._('1. Docker CLI & Compose over SSH (Native Remote Context)') }}:</b></p>
        <div style="position: relative; margin-bottom: 15px;">
            <pre id="snippet-ssh-docker" style="margin: 0; padding: 10px 45px 10px 12px; font-family: monospace; border-radius: 3px; background-color: #f5f5f5; border: 1px solid #ccc; white-space: pre-wrap; word-break: break-all;"></pre>
            <button class="btn btn-xs btn-default" type="button" onclick="copySnippet('snippet-ssh-docker', this)" title="{{ lang._('Copy') }}" style="position: absolute; top: 6px; right: 6px; z-index: 10; padding: 4px 8px;"><i class="fa fa-clipboard"></i></button>
        </div>

        <p><b>{{ lang._('2. Shell Environment Variable (Temporary)') }}:</b></p>
        <div style="position: relative; margin-bottom: 10px;">
            <pre id="snippet-docker-env" style="margin: 0; padding: 10px 45px 10px 12px; font-family: monospace; border-radius: 3px; background-color: #f5f5f5; border: 1px solid #ccc; white-space: pre-wrap; word-break: break-all;"></pre>
            <button class="btn btn-xs btn-default" type="button" onclick="copySnippet('snippet-docker-env', this)" title="{{ lang._('Copy') }}" style="position: absolute; top: 6px; right: 6px; z-index: 10; padding: 4px 8px;"><i class="fa fa-clipboard"></i></button>
        </div>

        <div class="alert alert-info" style="margin-top: 15px; margin-bottom: 5px;">
            <i class="fa fa-info-circle"></i>
            <b>{{ lang._('SSH Authentication Note:') }}</b><br>
            {{ lang._('Docker client connections route through SSH to the bhyve MicroVM. Ensure public key authentication is configured for root in System: Access: Users.') }}
        </div>
    </div>
</div>

<!-- Settings Form Panel -->
<div class="content-box tab-content">
    <div id="general-settings" class="tab-pane fade in active">
        {{ partial("layout_partials/base_form", ['fields': generalForm, 'id': 'frm_general-settings']) }}
    </div>
</div>

<div class="col-md-12" style="padding-left: 0; margin-top: 15px;">
    <button class="btn btn-primary" id="btn_save" type="button">
        <b>{{ lang._('Save & Apply') }}</b> <i id="btn_save_progress" class=""></i>
    </button>
</div>
