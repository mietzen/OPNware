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
    function updateRemoteGuide(data) {
        var host = (data.listen_address && data.listen_address !== '0.0.0.0') ? data.listen_address : (data.lan_ip || '{{ lanIp }}');
        var port = data.listen_port || '2376';
        var tcpActive = !!data.tcp_enabled;
        var tlsActive = !!data.tls_enabled;
        var sshActive = !!data.ssh_enabled;

        var tcpHost = 'tcp://' + host + ':' + port;
        var sshHost = 'ssh://root@' + (data.lan_ip || '{{ lanIp }}');

        $('#snippet-docker-env').text('export DOCKER_HOST="' + tcpHost + '"');
        $('#snippet-docker-context').text('docker context create opnsense-podman --docker "host=' + tcpHost + '"\ndocker context use opnsense-podman');
        $('#snippet-podman-remote').text('podman context create opnsense-tcp --docker "host=' + tcpHost + '"\npodman context use opnsense-tcp');
        $('#snippet-ssh-docker').text('docker context create opnsense-ssh --docker "host=' + sshHost + '"\ndocker context use opnsense-ssh');
        $('#snippet-ssh-podman').text('podman context create opnsense --docker "host=' + sshHost + '/var/run/podman/podman.sock"\npodman context use opnsense');
        $('#snippet-ssh-podman-legacy').text('podman system connection add opnsense ' + sshHost + '/var/run/podman/podman.sock\npodman -c opnsense ps');

        if (tlsActive) {
            $('#snippet-docker-tls').show().text('docker --tlsverify --tlscacert=ca.pem --tlscert=cert.pem --tlskey=key.pem -H ' + tcpHost + ' ps');
        } else {
            $('#snippet-docker-tls').hide();
        }

        if (!tcpActive && !sshActive) {
            $('#guide-warning-box').show();
            $('#guide-tabs-container').hide();
        } else {
            $('#guide-warning-box').hide();
            $('#guide-tabs-container').show();

            if (sshActive) {
                $('#tab-nav-ssh').show();
            } else {
                $('#tab-nav-ssh').hide();
            }

            if (tcpActive) {
                $('#tab-nav-docker-tcp').show();
                $('#tab-nav-podman-tcp').show();
            } else {
                $('#tab-nav-docker-tcp').hide();
                $('#tab-nav-podman-tcp').hide();
            }

            function selectGuideTab(navId, paneId) {
                var $activeNav = $('#guide-tabs-container .nav-tabs li.active');
                var $activePane = $('#guide-tabs-container .tab-content .tab-pane.active');
                if ($activeNav.attr('id') === navId && $activePane.attr('id') === paneId) {
                    return;
                }
                $activeNav.removeClass('active');
                $activePane.removeClass('active');
                $('#' + navId).addClass('active');
                $('#' + paneId).addClass('active');
            }

            if (sshActive) {
                selectGuideTab('tab-nav-ssh', 'tab-guide-ssh');
            } else if (tcpActive) {
                selectGuideTab('tab-nav-docker-tcp', 'tab-guide-docker');
            }
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
        ajaxGet('/api/podman/system/status', {}, function (data, status) {
            if (data) {
                var running = data.running ? '<span class="label label-success">{{ lang._("running") }}</span>' : '<span class="label label-default">{{ lang._("stopped") }}</span>';
                $('#status-running').html(running);
                $('#status-version').text(data.version || '--');
                $('#status-storage').text(data.storage || '--');
                $('#status-linux').text(data.linux_emulation || '--');
                $('#status-tcp').text(data.tcp_endpoint || '--');
                $('#status-interfaces').text(data.interfaces ? data.interfaces.toUpperCase() : 'LAN');
                updateRemoteGuide(data);
            }
        });
    }

    $(document).ready(function () {
        window.scrollTo(0, 0);
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
            window.scrollTo(0, 0);
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

<!-- Remote Connection Guide Card -->
<div class="content-box" style="margin-bottom: 20px; padding: 15px;">
    <h4 style="margin-top: 0;"><b>{{ lang._('Remote Client Setup & Connection Guide') }}</b></h4>
    <p class="text-muted">
        {{ lang._('Manage containers on this OPNsense firewall from your workstation using standard Docker CLI, Docker Compose, VS Code, or Podman Remote.') }}
    </p>

    <!-- Warning Alert when neither SSH nor TCP is available -->
    <div id="guide-warning-box" class="alert alert-warning" style="display: none; margin-bottom: 0;">
        <i class="fa fa-exclamation-triangle"></i>
        {{ lang._('Remote container management is currently unavailable because neither SSH nor the TCP REST Endpoint is enabled. Enable the TCP socket below (with TLS recommended) or enable SSH in System: Settings: Administration.') }}
    </div>

    <!-- Active Guides Tabs Container -->
    <div id="guide-tabs-container" style="display: none;">
        <ul class="nav nav-tabs" role="tablist" style="margin-bottom: 15px;">
            <li id="tab-nav-ssh" class="active"><a href="#tab-guide-ssh" data-toggle="tab"><b>{{ lang._('SSH Context (Docker & Podman)') }}</b></a></li>
            <li id="tab-nav-docker-tcp"><a href="#tab-guide-docker" data-toggle="tab"><b>{{ lang._('Docker CLI (TCP)') }}</b></a></li>
            <li id="tab-nav-podman-tcp"><a href="#tab-guide-podman" data-toggle="tab"><b>{{ lang._('Podman Remote (TCP)') }}</b></a></li>
        </ul>
        <div class="tab-content" style="padding: 0;">
            <!-- SSH Context Tab -->
            <div id="tab-guide-ssh" class="tab-pane active">
                <p><b>{{ lang._('1. Docker CLI & Compose over SSH (Native socket tunnel)') }}:</b></p>
                <div class="input-group" style="margin-bottom: 15px; width: 100%;">
                    <pre id="snippet-ssh-docker" style="margin: 0; font-family: monospace; border-radius: 3px 0 0 3px;"></pre>
                    <span class="input-group-btn" style="vertical-align: top;">
                        <button class="btn btn-default" type="button" onclick="copySnippet('snippet-ssh-docker', this)" title="{{ lang._('Copy') }}" style="height: 52px;"><i class="fa fa-clipboard"></i></button>
                    </span>
                </div>
                <p><b>{{ lang._('2. Podman Remote Context over SSH (Podman 6.1+)') }}:</b></p>
                <div class="input-group" style="margin-bottom: 15px; width: 100%;">
                    <pre id="snippet-ssh-podman" style="margin: 0; font-family: monospace; border-radius: 3px 0 0 3px;"></pre>
                    <span class="input-group-btn" style="vertical-align: top;">
                        <button class="btn btn-default" type="button" onclick="copySnippet('snippet-ssh-podman', this)" title="{{ lang._('Copy') }}" style="height: 52px;"><i class="fa fa-clipboard"></i></button>
                    </span>
                </div>
                <p><b>{{ lang._('3. Alternative: Podman System Connection (Legacy)') }}:</b></p>
                <div class="input-group" style="margin-bottom: 10px; width: 100%;">
                    <pre id="snippet-ssh-podman-legacy" style="margin: 0; font-family: monospace; border-radius: 3px 0 0 3px;"></pre>
                    <span class="input-group-btn" style="vertical-align: top;">
                        <button class="btn btn-default" type="button" onclick="copySnippet('snippet-ssh-podman-legacy', this)" title="{{ lang._('Copy') }}" style="height: 52px;"><i class="fa fa-clipboard"></i></button>
                    </span>
                </div>
                <div class="alert alert-info" style="margin-top: 15px; margin-bottom: 5px;">
                    <i class="fa fa-info-circle"></i>
                    <b>{{ lang._('Note on SSH Access & Root Privileges:') }}</b><br>
                    {{ lang._('FreeBSD executes Podman containers with root kernel privileges (rootless mode is not supported on FreeBSD). Therefore, SSH tunnels must connect as <code>root@<opnsense></code>. Ensure <b>Permit root user login</b> is enabled in <i>System: Settings: Administration</i> (public key authentication recommended), and configure public key authentication for the root user. Alternatively, use the Docker CLI (TCP) or Podman Remote (TCP) tabs above.') }}
                </div>
            </div>

            <!-- Docker TCP Tab -->
            <div id="tab-guide-docker" class="tab-pane">
                <p><b>{{ lang._('1. Temporary Shell Environment') }}:</b></p>
                <div class="input-group" style="margin-bottom: 15px; width: 100%;">
                    <pre id="snippet-docker-env" style="margin: 0; font-family: monospace; border-radius: 3px 0 0 3px;"></pre>
                    <span class="input-group-btn" style="vertical-align: top;">
                        <button class="btn btn-default" type="button" onclick="copySnippet('snippet-docker-env', this)" title="{{ lang._('Copy') }}" style="height: 38px;"><i class="fa fa-clipboard"></i></button>
                    </span>
                </div>
                <p><b>{{ lang._('2. Persistent Docker Context') }}:</b></p>
                <div class="input-group" style="margin-bottom: 10px; width: 100%;">
                    <pre id="snippet-docker-context" style="margin: 0; font-family: monospace; border-radius: 3px 0 0 3px;"></pre>
                    <span class="input-group-btn" style="vertical-align: top;">
                        <button class="btn btn-default" type="button" onclick="copySnippet('snippet-docker-context', this)" title="{{ lang._('Copy') }}" style="height: 52px;"><i class="fa fa-clipboard"></i></button>
                    </span>
                </div>
                <pre id="snippet-docker-tls" style="margin-top: 10px; font-family: monospace; display: none;"></pre>
            </div>

            <!-- Podman TCP Tab -->
            <div id="tab-guide-podman" class="tab-pane">
                <p><b>{{ lang._('Connect via Podman Remote Context') }}:</b></p>
                <div class="input-group" style="margin-bottom: 10px; width: 100%;">
                    <pre id="snippet-podman-remote" style="margin: 0; font-family: monospace; border-radius: 3px 0 0 3px;"></pre>
                    <span class="input-group-btn" style="vertical-align: top;">
                        <button class="btn btn-default" type="button" onclick="copySnippet('snippet-podman-remote', this)" title="{{ lang._('Copy') }}" style="height: 52px;"><i class="fa fa-clipboard"></i></button>
                    </span>
                </div>
            </div>
        </div>
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
