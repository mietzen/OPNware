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
    function formatRamDisplay(mb) {
        if (!mb) return '--';
        var n = parseInt(mb, 10);
        if (n >= 1024) {
            var gb = (n / 1024).toFixed(n % 1024 === 0 ? 0 : 1);
            return n + ' MB (' + gb + ' GB)';
        }
        return n + ' MB';
    }

    function updateRemoteGuide(data) {
        var lanIp = data.lan_ip || '{{ lanIp }}';
        var sshActive = !!data.ssh_enabled;
        var currentUser = data.current_user || '{{ currentUser }}' || 'root';
        var sshHost = 'ssh://' + currentUser + '@' + lanIp;

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

    function updateMetrics() {
        ajaxGet('/api/docker/general/metrics', {}, function (data, status) {
            if (status === 'success' && data) {
                if (data.running) {
                    $('#vm-metrics-banner').show();
                    $('#vm-metrics-stopped-banner').hide();

                    var cpuText = (data.cpu && data.cpu.display) ? data.cpu.display : '--';
                    var cpuPct = (data.cpu && data.cpu.percent !== undefined) ? data.cpu.percent : 0;
                    $('#vm-metric-cpu-text').text(cpuText);
                    $('#vm-metric-cpu-bar').css('width', Math.min(100, Math.max(2, cpuPct)) + '%').text(cpuPct + '%');
                    $('#vm-metric-cpu-bar').removeClass('progress-bar-danger progress-bar-warning').addClass(cpuPct > 85 ? 'progress-bar-danger' : (cpuPct > 65 ? 'progress-bar-warning' : 'progress-bar-info'));

                    var ramText = (data.ram && data.ram.display) ? data.ram.display : '--';
                    var ramPct = (data.ram && data.ram.percent !== undefined) ? data.ram.percent : 0;
                    $('#vm-metric-ram-text').text(ramText);
                    $('#vm-metric-ram-bar').css('width', Math.min(100, Math.max(2, ramPct)) + '%').text(ramPct + '%');
                    $('#vm-metric-ram-bar').removeClass('progress-bar-danger progress-bar-warning').addClass(ramPct > 90 ? 'progress-bar-danger' : (ramPct > 75 ? 'progress-bar-warning' : 'progress-bar-info'));

                    var diskText = (data.disk && data.disk.display) ? data.disk.display : '--';
                    var diskPct = (data.disk && data.disk.percent !== undefined) ? data.disk.percent : 0;
                    $('#vm-metric-disk-text').text(diskText);
                    $('#vm-metric-disk-bar').css('width', Math.min(100, Math.max(2, diskPct)) + '%').text(diskPct + '%');
                    $('#vm-metric-disk-bar').removeClass('progress-bar-danger progress-bar-warning').addClass(diskPct > 90 ? 'progress-bar-danger' : (diskPct > 75 ? 'progress-bar-warning' : 'progress-bar-success'));
                } else {
                    $('#vm-metrics-banner').hide();
                    $('#vm-metrics-stopped-banner').show();
                }
            }
        });
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
        updateMetrics();
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

        var initialSavedDisk = null;

        // Dynamic host hardware resource detection and sliders/inputs
        ajaxGet('/api/docker/general/host_resources', {}, function (data, status) {
            if (status === 'success' && data) {
                var hostCpus = parseInt(data.cpus || 2, 10);
                var rawMemMb = parseInt(data.memory_mb || 2048, 10);
                // Round host RAM to nearest 512MB
                var hostMemMb = Math.max(512, Math.round(rawMemMb / 512) * 512);
                var hostFreeGb = parseInt(data.disk_free_gb || 50, 10);

                // RAM max calculation: if host has < 4GB (4096MB) -> host / 2; else -> host - 2048MB
                var maxRamMb = (hostMemMb < 4096) ? Math.max(512, Math.floor(hostMemMb / 2)) : Math.max(512, hostMemMb - 2048);
                maxRamMb = Math.max(512, Math.round(maxRamMb / 512) * 512);

                // Disk max calculation: if host has < 20GB -> host / 2; else -> host - 10GB
                var minDiskGb = 2;
                var maxDiskGb = (hostFreeGb < 20) ? Math.max(minDiskGb, Math.floor(hostFreeGb / 2)) : Math.max(minDiskGb, hostFreeGb - 10);
                maxDiskGb = Math.max(minDiskGb, maxDiskGb);

                var cpuInput = $('#docker\\.general\\.cpus');
                var memInput = $('#docker\\.general\\.memory');
                var diskInput = $('#docker\\.general\\.disk_size');

                // 1. CPU Slider (Only Slider, Fixed positions: 1, 2, 3... max host cores)
                if (cpuInput.length > 0 && $('#slider_cpus_wrap').length === 0) {
                    var curCpu = parseInt(cpuInput.val() || 2, 10);
                    if (curCpu > hostCpus) curCpu = hostCpus;
                    if (curCpu < 1) curCpu = 1;
                    cpuInput.val(curCpu);
                    cpuInput.hide();

                    var cpuHtml = '<div id="slider_cpus_wrap" style="max-width: 400px; padding: 4px 0;">' +
                        '<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">' +
                        '<span class="badge badge-info" id="badge_cpus" style="font-size: 13px; padding: 4px 10px; background-color: #337ab7;">' + curCpu + ' vCPUs</span>' +
                        '<span class="text-muted" style="font-size: 11px;">Min: 1 &nbsp;|&nbsp; Max: ' + hostCpus + ' Cores</span>' +
                        '</div>' +
                        '<input type="range" id="slider_cpus" min="1" max="' + hostCpus + '" step="1" value="' + curCpu + '" style="width: 100%; cursor: pointer;">' +
                        '</div>';

                    cpuInput.after(cpuHtml);

                    $('#slider_cpus').on('input change', function () {
                        var val = $(this).val();
                        cpuInput.val(val);
                        $('#badge_cpus').text(val + ' vCPUs');
                    });
                }

                // 2. RAM Slider (Only Slider, Min 512MB, Step 512MB, Max calculated)
                if (memInput.length > 0 && $('#slider_mem_wrap').length === 0) {
                    var curMem = parseInt(memInput.val() || 2048, 10);
                    if (curMem > maxRamMb) curMem = maxRamMb;
                    if (curMem < 512) curMem = 512;
                    curMem = Math.round(curMem / 512) * 512;
                    memInput.val(curMem);
                    memInput.hide();

                    var possibleSteps = [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536];
                    var stepMarkersHtml = '<div style="display: flex; justify-content: space-between; font-size: 10px; color: #888; margin-top: 4px;">';
                    stepMarkersHtml += '<span>512MB</span>';
                    for (var i = 0; i < possibleSteps.length; i++) {
                        var s = possibleSteps[i];
                        if (s > 512 && s < maxRamMb && (s % 1024 === 0)) {
                            stepMarkersHtml += '<span>' + (s / 1024) + 'GB</span>';
                        }
                    }
                    if (maxRamMb > 512) {
                        stepMarkersHtml += '<span>' + (maxRamMb >= 1024 ? (maxRamMb / 1024).toFixed(maxRamMb % 1024 === 0 ? 0 : 1) + 'GB' : maxRamMb + 'MB') + '</span>';
                    }
                    stepMarkersHtml += '</div>';

                    var memHtml = '<div id="slider_mem_wrap" style="max-width: 400px; padding: 4px 0;">' +
                        '<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">' +
                        '<span class="badge badge-info" id="badge_mem" style="font-size: 13px; padding: 4px 10px; background-color: #337ab7;">' + formatRamDisplay(curMem) + '</span>' +
                        '<span class="text-muted" style="font-size: 11px;">Min: 512 MB &nbsp;|&nbsp; Max: ' + formatRamDisplay(maxRamMb) + '</span>' +
                        '</div>' +
                        '<input type="range" id="slider_mem" min="512" max="' + maxRamMb + '" step="512" value="' + curMem + '" style="width: 100%; cursor: pointer;">' +
                        stepMarkersHtml +
                        '</div>';

                    memInput.after(memHtml);

                    $('#slider_mem').on('input change', function () {
                        var val = parseInt($(this).val(), 10);
                        memInput.val(val);
                        $('#badge_mem').text(formatRamDisplay(val));
                    });
                }

                // 3. Disk Slider (Discrete Slider matching RAM style, Min 2GB, Step 1GB, Max calculated)
                if (diskInput.length > 0 && $('#slider_disk_wrap').length === 0) {
                    var curDisk = parseInt(diskInput.val() || 20, 10);
                    if (curDisk > maxDiskGb) curDisk = maxDiskGb;
                    if (curDisk < minDiskGb) curDisk = minDiskGb;
                    diskInput.val(curDisk);
                    initialSavedDisk = curDisk;
                    diskInput.hide();

                    var possibleDiskSteps = [2, 5, 10, 20, 50, 100, 200, 500, 1000];
                    var diskMarkersHtml = '<div style="display: flex; justify-content: space-between; font-size: 10px; color: #888; margin-top: 4px;">';
                    diskMarkersHtml += '<span>2GB</span>';
                    for (var dIdx = 0; dIdx < possibleDiskSteps.length; dIdx++) {
                        var ds = possibleDiskSteps[dIdx];
                        if (ds > 2 && ds < maxDiskGb) {
                            diskMarkersHtml += '<span>' + ds + 'GB</span>';
                        }
                    }
                    if (maxDiskGb > 2) {
                        diskMarkersHtml += '<span>' + maxDiskGb + 'GB</span>';
                    }
                    diskMarkersHtml += '</div>';

                    var diskHtml = '<div id="slider_disk_wrap" style="max-width: 400px; padding: 4px 0;">' +
                        '<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">' +
                        '<span class="badge badge-info" id="badge_disk" style="font-size: 13px; padding: 4px 10px; background-color: #337ab7;">' + curDisk + ' GB</span>' +
                        '<span class="text-muted" style="font-size: 11px;">Min: 2 GB &nbsp;|&nbsp; Max: ' + maxDiskGb + ' GB</span>' +
                        '</div>' +
                        '<input type="range" id="slider_disk" min="2" max="' + maxDiskGb + '" step="1" value="' + curDisk + '" style="width: 100%; cursor: pointer;">' +
                        diskMarkersHtml +
                        '</div>';

                    diskInput.after(diskHtml);

                    $('#slider_disk').on('input change', function () {
                        var val = parseInt($(this).val(), 10);
                        diskInput.val(val);
                        $('#badge_disk').text(val + ' GB');
                    });
                }

                var cpuHelp = "{{ lang._('Allocated virtual CPU cores for the Docker MicroVM (1 to ') }}" + hostCpus + "{{ lang._(' host cores).') }}";
                var memHelp = "{{ lang._('RAM memory allocated to the MicroVM in 512MB steps (512 MB to ') }}" + formatRamDisplay(maxRamMb) + "{{ lang._(').') }}";
                var diskHelp = "{{ lang._('Storage capacity for /var/lib/docker data disk in GB (2 GB to ') }}" + maxDiskGb + " GB" + "{{ lang._('). Increasing expands capacity safely; decreasing recreates data disk.') }}";

                cpuInput.closest('tr').find('small').text(cpuHelp);
                memInput.closest('tr').find('small').text(memHelp);
                diskInput.closest('tr').find('small').text(diskHelp);

            }
        });

        // 5-second periodic live metrics polling
        setInterval(function () {
            if (document.visibilityState === 'visible') {
                updateMetrics();
            }
        }, 5000);

        var rebootDialog = null;

        function performSave() {
            $('#btn_save_progress').addClass('fa fa-spinner fa-pulse');
            $('#btn_save').prop('disabled', true);

            var isEnabled = $('#docker\\.general\\.enabled').is(':checked');
            if (isEnabled) {
                rebootDialog = new BootstrapDialog({
                    title: '<i class="fa fa-spinner fa-spin" style="margin-right: 8px;"></i>' + '{{ lang._("Applying Configuration") }}',
                    message: '<div style="text-align: center; padding: 25px 15px;">' +
                             '<i class="fa fa-refresh fa-spin fa-3x text-primary" style="margin-bottom: 15px; display: block;"></i>' +
                             '<h4 style="margin: 0 0 8px 0; font-weight: 600;">' + '{{ lang._("Reconfiguring & Restarting Docker MicroVM...") }}' + '</h4>' +
                             '<p class="text-muted" style="margin: 0; font-size: 13px;">' + '{{ lang._("Please wait while the Alpine microVM applies disk, CPU, and network parameters.") }}' + '</p>' +
                             '</div>',
                    closable: false,
                    type: BootstrapDialog.TYPE_PRIMARY
                });
                rebootDialog.open();
            }

            saveFormToEndpoint('/api/docker/general/set', 'frm_general-settings', function () {
                ajaxCall('/api/docker/service/reconfigure', {}, function (data, status) {
                    $('#btn_save_progress').removeClass('fa fa-spinner fa-pulse');
                    $('#btn_save').prop('disabled', false);
                    initialSavedDisk = parseInt($('#docker\\.general\\.disk_size').val() || 20, 10);
                    updateServiceControlUI('docker');
                    updateStatus();
                    updateMetrics();
                    if (rebootDialog) {
                        setTimeout(function () {
                            rebootDialog.close();
                            rebootDialog = null;
                        }, 500);
                    }
                });
            }, false, function () {
                $('#btn_save_progress').removeClass('fa fa-spinner fa-pulse');
                $('#btn_save').prop('disabled', false);
                if (rebootDialog) {
                    rebootDialog.close();
                    rebootDialog = null;
                }
            });
        }

        $('#btn_save').click(function () {
            var curDiskVal = parseInt($('#docker\\.general\\.disk_size').val() || 20, 10);
            if (initialSavedDisk !== null && curDiskVal < initialSavedDisk) {
                BootstrapDialog.confirm({
                    title: '{{ lang._("Warning: Disk Size Reduction") }}',
                    message: '{{ lang._("Decreasing the data disk size from ") }}' + initialSavedDisk + ' GB {{ lang._("to ") }}' + curDiskVal + ' GB {{ lang._("will permanently destroy all existing containers, images, and volumes. A fresh data disk will be created.\\n\\nDo you want to proceed?") }}',
                    type: BootstrapDialog.TYPE_DANGER,
                    btnOKClass: 'btn-danger',
                    btnOKLabel: '{{ lang._("Recreate Disk & Save") }}',
                    btnCancelLabel: '{{ lang._("Cancel") }}',
                    callback: function (result) {
                        if (result) {
                            performSave();
                        }
                    }
                });
            } else {
                performSave();
            }
        });
    });

</script>

<!-- Live MicroVM Resource Usage Metrics Card (on top of Settings) -->
<div class="content-box" style="margin-bottom: 20px;">
    <div style="padding: 12px 15px 10px 15px; border-bottom: 1px solid #e5e5e5; display: flex; justify-content: space-between; align-items: center;">
        <h4 style="margin: 0; font-size: 14px; font-weight: bold; text-transform: uppercase;">
            <i class="fa fa-dashboard text-primary" style="margin-right: 8px;"></i>{{ lang._('MicroVM Live Resource Utilization') }}
        </h4>
        <button type="button" class="btn btn-xs btn-default" onclick="updateMetrics()" title="{{ lang._('Refresh Metrics') }}">
            <i class="fa fa-refresh"></i> {{ lang._('Refresh') }}
        </button>
    </div>

    <!-- Stopped state banner -->
    <div id="vm-metrics-stopped-banner" style="display: none; padding: 20px; text-align: center;" class="text-muted">
        <i class="fa fa-power-off fa-2x" style="margin-bottom: 8px; display: block; color: #bbb;"></i>
        <em>{{ lang._('Docker MicroVM is currently stopped. Start the Docker service to view live resource utilization.') }}</em>
    </div>

    <!-- Active metrics grid -->
    <div id="vm-metrics-banner" style="padding: 15px;">
        <div class="row">
            <!-- CPU Load -->
            <div class="col-xs-12 col-sm-4" style="margin-bottom: 10px;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 5px;">
                    <span style="font-weight: 600; font-size: 12px; text-transform: uppercase; color: #555;">
                        <i class="fa fa-microchip text-primary" style="margin-right: 5px;"></i>{{ lang._('vCPU Load (1m, 5m, 15m)') }}
                    </span>
                    <strong id="vm-metric-cpu-text" style="font-size: 12px;">--</strong>
                </div>
                <div class="progress" style="margin-bottom: 0; height: 16px; background-color: #eee; border-radius: 3px;">
                    <div id="vm-metric-cpu-bar" class="progress-bar progress-bar-info" role="progressbar" style="width: 0%; font-size: 10px; line-height: 16px; font-weight: bold;">0%</div>
                </div>
            </div>

            <!-- RAM Usage -->
            <div class="col-xs-12 col-sm-4" style="margin-bottom: 10px;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 5px;">
                    <span style="font-weight: 600; font-size: 12px; text-transform: uppercase; color: #555;">
                        <i class="fa fa-area-chart text-info" style="margin-right: 5px;"></i>{{ lang._('RAM Usage') }}
                    </span>
                    <strong id="vm-metric-ram-text" style="font-size: 12px;">--</strong>
                </div>
                <div class="progress" style="margin-bottom: 0; height: 16px; background-color: #eee; border-radius: 3px;">
                    <div id="vm-metric-ram-bar" class="progress-bar progress-bar-info" role="progressbar" style="width: 0%; font-size: 10px; line-height: 16px; font-weight: bold;">0%</div>
                </div>
            </div>

            <!-- Disk Usage -->
            <div class="col-xs-12 col-sm-4" style="margin-bottom: 10px;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 5px;">
                    <span style="font-weight: 600; font-size: 12px; text-transform: uppercase; color: #555;">
                        <i class="fa fa-database text-warning" style="margin-right: 5px;"></i>{{ lang._('Data Disk (/var/lib/docker)') }}
                    </span>
                    <strong id="vm-metric-disk-text" style="font-size: 12px;">--</strong>
                </div>
                <div class="progress" style="margin-bottom: 0; height: 16px; background-color: #eee; border-radius: 3px;">
                    <div id="vm-metric-disk-bar" class="progress-bar progress-bar-success" role="progressbar" style="width: 0%; font-size: 10px; line-height: 16px; font-weight: bold;">0%</div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Live Docker Status Card -->
<div class="content-box" style="margin-bottom: 20px;">
    <div class="table-responsive">
        <table class="table table-striped table-condensed" id="tbl_docker_status" style="margin-bottom: 0;">
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
            {{ lang._('Docker client connections route securely through SSH to this OPNsense firewall. Any administrative user in the wheel or admins group can manage containers seamlessly without sudo.') }}
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
