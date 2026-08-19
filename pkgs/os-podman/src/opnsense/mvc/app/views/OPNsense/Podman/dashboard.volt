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
    var autoRefreshInterval = null;
    var currentLogContainerId = null;
    var currentCliContainerId = null;
    var cliHistory = [];
    var cliHistoryIdx = -1;

    function ansiToHtml(str) {
        if (!str) return '';
        var html = str
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");

        var colors = {
            '30': '#4e4e4e', '31': '#ff6b68', '32': '#5af78e', '33': '#f3f99d',
            '34': '#57c7ff', '35': '#ff6ac1', '36': '#9aedfe', '37': '#f1f1f0',
            '90': '#767676', '91': '#e74c3c', '92': '#2ecc71', '93': '#f1c40f',
            '94': '#3498db', '95': '#9b59b6', '96': '#1abc9c', '97': '#ecf0f1'
        };

        var openSpans = 0;
        html = html.replace(/\x1b\[([0-9;]+)m/g, function(match, codeStr) {
            var codes = codeStr.split(';');
            var styles = [];
            var reset = false;

            for (var i = 0; i < codes.length; i++) {
                var code = codes[i];
                if (code === '0' || code === '') {
                    reset = true;
                } else if (code === '1') {
                    styles.push('font-weight: bold;');
                } else if (code === '4') {
                    styles.push('text-decoration: underline;');
                } else if (colors[code]) {
                    styles.push('color: ' + colors[code] + ';');
                }
            }

            var res = '';
            if (reset) {
                while (openSpans > 0) {
                    res += '</span>';
                    openSpans--;
                }
            }
            if (styles.length > 0) {
                res += '<span style="' + styles.join(' ') + '">';
                openSpans++;
            }
            return res;
        });

        while (openSpans > 0) {
            html += '</span>';
            openSpans--;
        }

        html = html.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '');
        return html;
    }

    function refreshActiveTab() {
        var activeTab = $('#maintabs li.active a').attr('href');
        loadSystemDf();
        if (activeTab === '#tab-containers') {
            loadContainers();
        } else if (activeTab === '#tab-images') {
            loadImages();
        } else if (activeTab === '#tab-volumes') {
            loadVolumes();
        } else if (activeTab === '#tab-networks') {
            loadNetworks();
        }
    }

    function loadSystemDf() {
        ajaxGet('/api/podman/system/df', {}, function (data, status) {
            if (data && Array.isArray(data.items)) {
                var totalContainers = 0;
                var activeContainers = 0;
                var totalImages = 0;
                var activeImages = 0;
                var totalVolumes = 0;
                var reclaimableStr = '0B';

                $.each(data.items, function (idx, item) {
                    if (item.Type === 'Containers') {
                        totalContainers = item.Total || 0;
                        activeContainers = item.Active || 0;
                    } else if (item.Type === 'Images') {
                        totalImages = item.Total || 0;
                        activeImages = item.Active || 0;
                        if (item.Reclaimable) {
                            reclaimableStr = item.Reclaimable;
                        }
                    } else if (item.Type === 'Local Volumes') {
                        totalVolumes = item.Total || 0;
                    }
                });

                $('#stat-containers').text(activeContainers + ' / ' + totalContainers + ' Running');
                $('#stat-images').text(activeImages + ' / ' + totalImages + ' Active');
                $('#stat-volumes').text(totalVolumes + ' Volumes');
                $('#stat-reclaimable').text(reclaimableStr);
            }
        });
    }

    var cachedContainers = [];

    function formatTimestamp(val) {
        if (!val) return '--';
        var d = null;
        if (typeof val === 'number') {
            d = new Date(val > 1e11 ? val : val * 1000);
        } else if (/^\d+$/.test(val)) {
            var n = parseInt(val, 10);
            d = new Date(n > 1e11 ? n : n * 1000);
        } else {
            d = new Date(val);
        }
        if (!d || isNaN(d.getTime())) {
            return $('<div>').text(val).html();
        }
        var now = new Date();
        var diffSec = Math.floor((now - d) / 1000);
        var rel = '';
        if (diffSec < 60) {
            rel = '{{ lang._("just now") }}';
        } else if (diffSec < 3600) {
            var m = Math.floor(diffSec / 60);
            rel = m + (m === 1 ? ' {{ lang._("min ago") }}' : ' {{ lang._("mins ago") }}');
        } else if (diffSec < 86400) {
            var h = Math.floor(diffSec / 3600);
            rel = h + (h === 1 ? ' {{ lang._("hour ago") }}' : ' {{ lang._("hours ago") }}');
        } else {
            var days = Math.floor(diffSec / 86400);
            rel = days + (days === 1 ? ' {{ lang._("day ago") }}' : ' {{ lang._("days ago") }}');
        }
        var iso = d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0') + ' ' + String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
        return '<span title="' + iso + '">' + rel + ' <small class="text-muted">(' + iso + ')</small></span>';
    }

    function loadContainers() {
        ajaxGet('/api/podman/containers/list', {}, function (data, status) {
            var $tbody = $('#grid-containers tbody');
            var items = (data && data.items) ? data.items : [];
            cachedContainers = items;
            if (items.length === 0) {
                $tbody.html('<tr><td colspan="7" class="text-center"><em>{{ lang._("No containers found") }}</em></td></tr>');
                return;
            }

            // Fetch live stats in parallel
            ajaxGet('/api/podman/containers/stats', {}, function(statsData) {
                var statsMap = {};
                if (statsData && Array.isArray(statsData.items)) {
                    $.each(statsData.items, function(i, st) {
                        var sid = (st.Id || st.ID || st.Container || '').substring(0, 12);
                        statsMap[sid] = st;
                        if (st.Name) {
                            statsMap[st.Name] = st;
                        }
                    });
                }

                var rows = '';
                $.each(items, function (idx, c) {
                    var cid = (c.Id || c.ID || '').substring(0, 12);
                    var names = Array.isArray(c.Names) ? c.Names.join(', ') : (c.Names || '');
                    var image = c.Image || '';
                    var state = c.State || c.Status || '';
                    var created = c.Created || c.CreatedAt || '';

                    var isRunning = (state.toLowerCase().indexOf('up') !== -1 || state.toLowerCase() === 'running');
                    var badgeClass = isRunning ? 'label-success' : 'label-default';

                    var stat = statsMap[cid] || (names ? statsMap[names] : null);
                    var resourceBadges = '--';
                    if (isRunning && stat) {
                        var cpu = stat.CPUPerc || stat.CPU || '--';
                        var mem = stat.MemUsage || stat.Mem || '--';
                        resourceBadges = '<span class="label label-info" title="{{ lang._("CPU Usage") }}"><i class="fa fa-dashboard"></i> ' + cpu + '</span> <span class="label label-primary" title="{{ lang._("Memory Usage") }}"><i class="fa fa-microchip"></i> ' + mem + '</span>';
                    } else if (isRunning) {
                        resourceBadges = '<span class="text-muted"><i class="fa fa-dashboard"></i> --</span>';
                    }

                    // Merged Start/Stop button
                    var startStopBtn = '';
                    if (isRunning) {
                        startStopBtn = '<button class="btn btn-xs btn-default act-stop" data-id="' + cid + '" title="{{ lang._("Stop Container") }}"><i class="fa fa-stop text-warning"></i></button> ';
                    } else {
                        startStopBtn = '<button class="btn btn-xs btn-default act-start" data-id="' + cid + '" title="{{ lang._("Start Container") }}"><i class="fa fa-play text-success"></i></button> ';
                    }

                    // Restart, Kill, CLI actions (muted grey face when disabled)
                    var restartBtn = isRunning
                        ? '<button class="btn btn-xs btn-default act-restart" data-id="' + cid + '" title="{{ lang._("Restart") }}"><i class="fa fa-refresh text-info"></i></button> '
                        : '<button class="btn btn-xs btn-default" disabled="disabled" title="{{ lang._("Restart (Container stopped)") }}"><i class="fa fa-refresh text-muted"></i></button> ';

                    var killBtn = isRunning
                        ? '<button class="btn btn-xs btn-default act-kill" data-id="' + cid + '" title="{{ lang._("Force Stop") }}"><i class="fa fa-bolt text-danger"></i></button> '
                        : '<button class="btn btn-xs btn-default" disabled="disabled" title="{{ lang._("Force Stop (Container stopped)") }}"><i class="fa fa-bolt text-muted"></i></button> ';

                    var cliBtn = isRunning
                        ? '<button class="btn btn-xs btn-default act-cli" data-id="' + cid + '" data-name="' + $('<div>').text(names).html() + '" title="{{ lang._("Container CLI") }}"><i class="fa fa-terminal text-warning"></i></button> '
                        : '<button class="btn btn-xs btn-default" disabled="disabled" title="{{ lang._("Container CLI (Container stopped)") }}"><i class="fa fa-terminal text-muted"></i></button> ';

                    var logsBtn = '<button class="btn btn-xs btn-default act-logs" data-id="' + cid + '" data-name="' + $('<div>').text(names).html() + '" title="{{ lang._("View Logs") }}"><i class="fa fa-file-text-o text-primary"></i></button> ';
                    var inspectBtn = '<button class="btn btn-xs btn-default act-inspect" data-id="' + cid + '" data-name="' + $('<div>').text(names).html() + '" title="{{ lang._("Inspect Container") }}"><i class="fa fa-info-circle text-info"></i></button> ';

                    // Delete or Lock button
                    var deleteBtn = '';
                    if (isRunning) {
                        deleteBtn = '<button class="btn btn-xs btn-default" disabled="disabled" title="{{ lang._("Cannot delete running container. Stop container first.") }}"><i class="fa fa-lock text-muted"></i></button>';
                    } else {
                        deleteBtn = '<button class="btn btn-xs btn-default act-delete-container" data-id="' + cid + '" data-name="' + $('<div>').text(names).html() + '" title="{{ lang._("Delete Container") }}"><i class="fa fa-trash text-danger"></i></button>';
                    }

                    var actions = startStopBtn + restartBtn + killBtn + cliBtn + logsBtn + inspectBtn + deleteBtn;

                    rows += '<tr>' +
                        '<td><code>' + cid + '</code></td>' +
                        '<td><strong>' + $('<div>').text(names).html() + '</strong></td>' +
                        '<td>' + $('<div>').text(image).html() + '</td>' +
                        '<td><span class="label ' + badgeClass + '">' + $('<div>').text(state).html() + '</span></td>' +
                        '<td>' + resourceBadges + '</td>' +
                        '<td>' + formatTimestamp(created) + '</td>' +
                        '<td>' + actions + '</td>' +
                        '</tr>';
                });
                $tbody.html(rows);
            });
        });
    }

    function loadImages() {
        ajaxGet('/api/podman/images/list', {}, function (data, status) {
            var $tbody = $('#grid-images tbody');
            var items = (data && data.items) ? data.items : [];
            if (items.length === 0) {
                $tbody.html('<tr><td colspan="5" class="text-center"><em>{{ lang._("No images found") }}</em></td></tr>');
                return;
            }

            var usedImages = {};
            $.each(cachedContainers, function(idx, c) {
                var cimg = c.Image || '';
                var cname = Array.isArray(c.Names) ? c.Names[0] : (c.Names || c.Id);
                usedImages[cimg] = cname;
                if (c.ImageID) {
                    usedImages[c.ImageID.substring(0, 12)] = cname;
                }
            });

            var rows = '';
            $.each(items, function (idx, img) {
                var repo = Array.isArray(img.Names) ? img.Names.join(', ') : (img.Repository || img.History || 'none');
                var iid = (img.Id || img.ID || '').substring(0, 12);
                var size = img.Size ? (typeof img.Size === 'number' ? (img.Size / (1024*1024)).toFixed(1) + ' MB' : img.Size) : '';
                var created = img.Created || img.CreatedAt || '';

                var inUseBy = usedImages[repo] || usedImages[iid];
                var actions = '';
                if (inUseBy) {
                    actions = '<button class="btn btn-xs btn-default" disabled="disabled" title="{{ lang._("Image is currently used by container: ") }}' + $('<div>').text(inUseBy).html() + '"><i class="fa fa-lock text-muted"></i></button>';
                } else {
                    actions = '<button class="btn btn-xs btn-default act-delete-image" data-id="' + iid + '" data-name="' + $('<div>').text(repo).html() + '" title="{{ lang._("Delete Image") }}"><i class="fa fa-trash text-danger"></i></button>';
                }

                rows += '<tr>' +
                    '<td><strong>' + $('<div>').text(repo).html() + '</strong></td>' +
                    '<td><code>' + iid + '</code></td>' +
                    '<td>' + size + '</td>' +
                    '<td>' + formatTimestamp(created) + '</td>' +
                    '<td>' + actions + '</td>' +
                    '</tr>';
            });
            $tbody.html(rows);
        });
    }

    function loadVolumes() {
        ajaxGet('/api/podman/volumes/list', {}, function (data, status) {
            var $tbody = $('#grid-volumes tbody');
            var items = (data && data.items) ? data.items : [];
            if (items.length === 0) {
                $tbody.html('<tr><td colspan="4" class="text-center"><em>{{ lang._("No volumes found") }}</em></td></tr>');
                return;
            }

            var usedVolumes = {};
            $.each(cachedContainers, function(idx, c) {
                if (Array.isArray(c.Mounts)) {
                    $.each(c.Mounts, function(mIdx, m) {
                        if (m.Name) {
                            usedVolumes[m.Name] = Array.isArray(c.Names) ? c.Names[0] : c.Names;
                        }
                    });
                }
            });

            var rows = '';
            $.each(items, function (idx, v) {
                var vname = v.Name || '';
                var inUseBy = usedVolumes[vname];
                var actions = '';
                if (inUseBy) {
                    actions = '<button class="btn btn-xs btn-default" disabled="disabled" title="{{ lang._("Volume is in use by container: ") }}' + $('<div>').text(inUseBy).html() + '"><i class="fa fa-lock text-muted"></i></button>';
                } else {
                    actions = '<button class="btn btn-xs btn-default act-delete-volume" data-name="' + $('<div>').text(vname).html() + '" title="{{ lang._("Delete Volume") }}"><i class="fa fa-trash text-danger"></i></button>';
                }

                rows += '<tr>' +
                    '<td><strong>' + $('<div>').text(vname).html() + '</strong></td>' +
                    '<td>' + $('<div>').text(v.Driver || '').html() + '</td>' +
                    '<td><code>' + $('<div>').text(v.Mountpoint || '').html() + '</code></td>' +
                    '<td>' + actions + '</td>' +
                    '</tr>';
            });
            $tbody.html(rows);
        });
    }

    function loadNetworks() {
        ajaxGet('/api/podman/networks/list', {}, function (data, status) {
            var $tbody = $('#grid-networks tbody');
            var items = (data && data.items) ? data.items : [];
            if (items.length === 0) {
                $tbody.html('<tr><td colspan="5" class="text-center"><em>{{ lang._("No networks found") }}</em></td></tr>');
                return;
            }
            var rows = '';
            $.each(items, function (idx, net) {
                var netName = net.Name || net.name || '';
                var subnets = '';
                if (Array.isArray(net.Subnets)) {
                    subnets = net.Subnets.map(function(s) { return s.Subnet || ''; }).join(', ');
                }
                var isDefault = (netName === 'podman' || netName === 'none' || netName === 'host');
                var actions = '';
                if (!isDefault) {
                    actions = '<button class="btn btn-xs btn-default act-delete-network" data-name="' + $('<div>').text(netName).html() + '" title="{{ lang._("Delete Network") }}"><i class="fa fa-trash text-danger"></i></button>';
                } else {
                    actions = '<button class="btn btn-xs btn-default" disabled="disabled" title="{{ lang._("Default system network cannot be deleted") }}"><i class="fa fa-lock text-muted"></i></button>';
                }

                rows += '<tr>' +
                    '<td><strong>' + $('<div>').text(netName).html() + '</strong></td>' +
                    '<td><code>' + ((net.ID || net.Id || '').substring(0, 12)) + '</code></td>' +
                    '<td>' + $('<div>').text(net.Driver || 'bridge').html() + '</td>' +
                    '<td>' + $('<div>').text(subnets).html() + '</td>' +
                    '<td>' + actions + '</td>' +
                    '</tr>';
            });
            $tbody.html(rows);
        });
    }

    function showContainerLogs(cid, name) {
        currentLogContainerId = cid;
        $('#modal-logs-title').text('{{ lang._("Container Logs") }}: ' + (name || cid));
        $('#modal-logs-body').text('{{ lang._("Loading logs...") }}');
        $('#modal-logs').modal('show');
        fetchLogsContent();
    }

    function fetchLogsContent() {
        if (!currentLogContainerId) return;
        ajaxGet('/api/podman/containers/logs/' + currentLogContainerId, {}, function (data, status) {
            var text = '';
            if (data && data.output) {
                text = data.output;
            } else if (data && data.message) {
                text = data.message;
            } else {
                text = '({{ lang._("No log output") }})';
            }
            $('#modal-logs-body').html(ansiToHtml(text));
            var pre = document.getElementById('modal-logs-body');
            if (pre) {
                pre.scrollTop = pre.scrollHeight;
            }
        });
    }

    function showContainerInspect(cid, name) {
        $('#modal-inspect-title').text('{{ lang._("Container Inspection") }}: ' + (name || cid));
        $('#modal-inspect-body').text('{{ lang._("Loading inspection data...") }}');
        $('#modal-inspect').modal('show');
        ajaxGet('/api/podman/containers/inspect/' + cid, {}, function (data, status) {
            var text = '';
            if (data && data.items) {
                text = JSON.stringify(data.items, null, 2);
            } else if (data && data.output) {
                text = data.output;
            } else {
                text = JSON.stringify(data, null, 2);
            }
            $('#modal-inspect-body').text(text);
        });
    }

    var currentCliXhr = null;

    function resetCliUi() {
        $('#btn-cli-stop').hide();
        $('#btn-cli-run').show();
        var el = document.getElementById('modal-cli-console');
        if (el) el.scrollTop = el.scrollHeight;
        $('#cli-cmd-input').focus();
    }

    function showContainerCli(cid, name) {
        currentCliContainerId = cid;
        cliHistoryIdx = -1;
        $('#modal-cli-title').text('{{ lang._("Container CLI") }}: ' + (name || cid));
        $('#modal-cli-console').html('<span style="color: #767676;">{{ lang._("Connected to container") }} ' + cid + '. {{ lang._("Enter commands below.") }}\n</span>');
        $('#cli-cmd-input').val('');
        resetCliUi();
        $('#modal-cli').modal('show');
        setTimeout(function() { $('#cli-cmd-input').focus(); }, 500);
    }

    function stopContainerCli() {
        if (currentCliXhr) {
            currentCliXhr.abort();
            currentCliXhr = null;
        }
        var $console = $('#modal-cli-console');
        $console.append('<span style="color: #ff6b68;">^C ({{ lang._("command aborted") }})\n</span>');
        resetCliUi();
    }

    function runContainerCli() {
        var cmd = $('#cli-cmd-input').val().trim();
        if (!cmd || !currentCliContainerId) return;
        var shell = $('#cli-shell').val().trim() || '/bin/sh';

        cliHistory.push(cmd);
        cliHistoryIdx = -1;
        $('#cli-cmd-input').val('');

        var $console = $('#modal-cli-console');
        $console.append('<span style="color: #57c7ff;">$ ' + $('<div>').text(cmd).html() + '\n</span>');

        $('#btn-cli-run').hide();
        $('#btn-cli-stop').show();

        currentCliXhr = $.ajax({
            url: '/api/podman/containers/exec/' + currentCliContainerId,
            type: 'POST',
            dataType: 'json',
            data: {cmd: cmd, shell: shell},
            success: function (data) {
                currentCliXhr = null;
                var out = '';
                if (data && data.output) {
                    out = data.output;
                } else if (data && data.message) {
                    out = data.message;
                } else {
                    out = '(no output)';
                }
                $console.append(ansiToHtml(out) + '\n');
                resetCliUi();
            },
            error: function (xhr, status, error) {
                currentCliXhr = null;
                if (status !== 'abort') {
                    $console.append('<span style="color: #ff6b68;">{{ lang._("Execution error") }}: ' + $('<div>').text(error || status).html() + '\n</span>');
                }
                resetCliUi();
            }
        });
    }

    function confirmDelete(title, message, endpoint) {
        BootstrapDialog.confirm({
            title: title,
            message: message,
            type: BootstrapDialog.TYPE_DANGER,
            btnOKClass: 'btn-danger',
            btnOKLabel: '{{ lang._("Delete") }}',
            callback: function (result) {
                if (result) {
                    ajaxCall(endpoint, {}, function () {
                        refreshActiveTab();
                    });
                }
            }
        });
    }

    $(document).ready(function () {
        updateServiceControlUI('podman');
        loadSystemDf();
        loadContainers();
        loadImages();
        loadVolumes();
        loadNetworks();

        autoRefreshInterval = setInterval(refreshActiveTab, 5000);

        $('#maintabs a[data-toggle="tab"]').on('shown.bs.tab', function () {
            refreshActiveTab();
        });

        // Lifecycle Actions
        $(document).on('click', '.act-start, .act-stop, .act-restart, .act-kill', function () {
            if ($(this).is(':disabled')) return;
            var cid = $(this).data('id');
            var action = 'start';
            if ($(this).hasClass('act-stop')) action = 'stop';
            else if ($(this).hasClass('act-restart')) action = 'restart';
            else if ($(this).hasClass('act-kill')) action = 'kill';

            ajaxCall('/api/podman/containers/' + action + '/' + cid, {}, function () {
                loadContainers();
                loadSystemDf();
            });
        });

        // Logs, Inspect & CLI
        $(document).on('click', '.act-logs', function () {
            var cid = $(this).data('id');
            var name = $(this).data('name');
            showContainerLogs(cid, name);
        });

        $(document).on('click', '.act-inspect', function () {
            var cid = $(this).data('id');
            var name = $(this).data('name');
            showContainerInspect(cid, name);
        });

        $(document).on('click', '.act-cli', function () {
            var cid = $(this).data('id');
            var name = $(this).data('name');
            if ($(this).is(':disabled')) return;
            showContainerCli(cid, name);
        });

        $('#btn_refresh_modal_logs').click(function () {
            fetchLogsContent();
        });

        $('#btn_clear_cli').click(function () {
            $('#modal-cli-console').html('<span style="color: #767676;">{{ lang._("Console cleared.") }}\n</span>');
        });

        $('#btn-cli-run').click(function () {
            runContainerCli();
        });

        $('#btn-cli-stop').click(function () {
            stopContainerCli();
        });

        $('#cli-cmd-input').keydown(function (e) {
            if (e.which === 13) { // Enter
                e.preventDefault();
                runContainerCli();
            } else if (e.ctrlKey && e.which === 67) { // Ctrl+C
                e.preventDefault();
                stopContainerCli();
            } else if (e.which === 38) { // Arrow Up (history back)
                e.preventDefault();
                if (cliHistory.length > 0) {
                    if (cliHistoryIdx === -1) {
                        cliHistoryIdx = cliHistory.length - 1;
                    } else if (cliHistoryIdx > 0) {
                        cliHistoryIdx--;
                    }
                    $('#cli-cmd-input').val(cliHistory[cliHistoryIdx]);
                }
            } else if (e.which === 40) { // Arrow Down (history forward)
                e.preventDefault();
                if (cliHistoryIdx !== -1) {
                    if (cliHistoryIdx < cliHistory.length - 1) {
                        cliHistoryIdx++;
                        $('#cli-cmd-input').val(cliHistory[cliHistoryIdx]);
                    } else {
                        cliHistoryIdx = -1;
                        $('#cli-cmd-input').val('');
                    }
                }
            }
        });

        $('#modal-cli').on('hidden.bs.modal', function () {
            if (currentCliXhr) {
                currentCliXhr.abort();
                currentCliXhr = null;
            }
            $('#btn-cli-stop').hide();
            $('#btn-cli-run').show();
        });

        // Deletion
        $(document).on('click', '.act-delete-container', function () {
            if ($(this).is(':disabled')) return;
            var cid = $(this).data('id');
            var name = $(this).data('name');
            confirmDelete(
                '{{ lang._("Delete Container") }}',
                '{{ lang._("Are you sure you want to delete container") }} ' + (name ? name + ' (' + cid + ')' : cid) + '?',
                '/api/podman/containers/delete/' + cid
            );
        });

        $(document).on('click', '.act-delete-image', function () {
            var iid = $(this).data('id');
            var name = $(this).data('name');
            confirmDelete(
                '{{ lang._("Delete Image") }}',
                '{{ lang._("Are you sure you want to delete image") }} ' + (name ? name + ' (' + iid + ')' : iid) + '?',
                '/api/podman/images/delete/' + iid
            );
        });

        $(document).on('click', '.act-delete-volume', function () {
            var name = $(this).data('name');
            confirmDelete(
                '{{ lang._("Delete Volume") }}',
                '{{ lang._("Are you sure you want to delete volume") }} ' + name + '?',
                '/api/podman/volumes/delete/' + encodeURIComponent(name)
            );
        });

        $(document).on('click', '.act-delete-network', function () {
            var name = $(this).data('name');
            confirmDelete(
                '{{ lang._("Delete Network") }}',
                '{{ lang._("Are you sure you want to delete network") }} ' + name + '?',
                '/api/podman/networks/delete/' + encodeURIComponent(name)
            );
        });

        // System Prune
        $('#btn_system_prune').click(function () {
            BootstrapDialog.confirm({
                title: '{{ lang._("System Prune") }}',
                message: '{{ lang._("This will remove all stopped containers and dangling images. Reclaim unused storage?") }}',
                type: BootstrapDialog.TYPE_WARNING,
                btnOKClass: 'btn-warning',
                btnOKLabel: '{{ lang._("Prune") }}',
                callback: function (result) {
                    if (result) {
                        $('#btn_system_prune_progress').addClass('fa fa-spinner fa-pulse');
                        ajaxCall('/api/podman/system/prune', {}, function () {
                            $('#btn_system_prune_progress').removeClass('fa fa-spinner fa-pulse');
                            refreshActiveTab();
                        });
                    }
                }
            });
        });
    });
</script>

<!-- System Overview Stats Bar -->
<div class="row" style="margin-bottom: 15px;">
    <div class="col-xs-12 col-sm-6 col-md-3">
        <div class="panel panel-default" style="margin-bottom: 0;">
            <div class="panel-body" style="padding: 10px 15px;">
                <div class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._('Containers') }}</div>
                <div style="font-size: 18px; font-weight: bold;" id="stat-containers">--</div>
            </div>
        </div>
    </div>
    <div class="col-xs-12 col-sm-6 col-md-3">
        <div class="panel panel-default" style="margin-bottom: 0;">
            <div class="panel-body" style="padding: 10px 15px;">
                <div class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._('Images') }}</div>
                <div style="font-size: 18px; font-weight: bold;" id="stat-images">--</div>
            </div>
        </div>
    </div>
    <div class="col-xs-12 col-sm-6 col-md-3">
        <div class="panel panel-default" style="margin-bottom: 0;">
            <div class="panel-body" style="padding: 10px 15px;">
                <div class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._('Volumes') }}</div>
                <div style="font-size: 18px; font-weight: bold;" id="stat-volumes">--</div>
            </div>
        </div>
    </div>
    <div class="col-xs-12 col-sm-6 col-md-3">
        <div class="panel panel-default" style="margin-bottom: 0;">
            <div class="panel-body" style="padding: 10px 15px; display: flex; justify-content: space-between; align-items: center;">
                <div>
                    <div class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._('Reclaimable') }}</div>
                    <div style="font-size: 18px; font-weight: bold; color: #f0ad4e;" id="stat-reclaimable">--</div>
                </div>
                <div>
                    <button class="btn btn-sm btn-warning" id="btn_system_prune" title="{{ lang._('Prune unused containers and images') }}">
                        <i class="fa fa-trash-o"></i> {{ lang._('Prune') }} <i id="btn_system_prune_progress"></i>
                    </button>
                </div>
            </div>
        </div>
    </div>
</div>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs" style="margin-bottom: 0;">
    <li class="active"><a data-toggle="tab" href="#tab-containers"><i class="fa fa-cubes"></i> {{ lang._('Containers') }}</a></li>
    <li><a data-toggle="tab" href="#tab-images"><i class="fa fa-clone"></i> {{ lang._('Images') }}</a></li>
    <li><a data-toggle="tab" href="#tab-volumes"><i class="fa fa-database"></i> {{ lang._('Volumes') }}</a></li>
    <li><a data-toggle="tab" href="#tab-networks"><i class="fa fa-sitemap"></i> {{ lang._('Networks') }}</a></li>
</ul>

<div class="content-box tab-content" style="padding: 0;">
    <!-- Containers Tab -->
    <div id="tab-containers" class="tab-pane fade in active">
        <div class="table-responsive">
            <table class="table table-striped table-condensed table-hover" id="grid-containers" style="margin-bottom: 0;">
                <thead>
                    <tr>
                        <th style="width: 120px;">{{ lang._('Container ID') }}</th>
                        <th>{{ lang._('Name') }}</th>
                        <th>{{ lang._('Image') }}</th>
                        <th style="width: 100px;">{{ lang._('Status') }}</th>
                        <th style="width: 150px;">{{ lang._('CPU / Memory') }}</th>
                        <th style="width: 180px;">{{ lang._('Created') }}</th>
                        <th style="width: 230px;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="7" class="text-center" id="containers-loading"><i class="fa fa-spinner fa-pulse"></i> {{ lang._('Loading containers...') }}</td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Images Tab -->
    <div id="tab-images" class="tab-pane fade">
        <div class="table-responsive">
            <table class="table table-striped table-condensed table-hover" id="grid-images" style="margin-bottom: 0;">
                <thead>
                    <tr>
                        <th>{{ lang._('Repository:Tag') }}</th>
                        <th style="width: 140px;">{{ lang._('Image ID') }}</th>
                        <th style="width: 120px;">{{ lang._('Size') }}</th>
                        <th>{{ lang._('Created') }}</th>
                        <th style="width: 80px;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="5" class="text-center"><em>{{ lang._('No images found') }}</em></td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Volumes Tab -->
    <div id="tab-volumes" class="tab-pane fade">
        <div class="table-responsive">
            <table class="table table-striped table-condensed table-hover" id="grid-volumes" style="margin-bottom: 0;">
                <thead>
                    <tr>
                        <th>{{ lang._('Volume Name') }}</th>
                        <th style="width: 140px;">{{ lang._('Driver') }}</th>
                        <th>{{ lang._('Mount Point') }}</th>
                        <th style="width: 80px;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="4" class="text-center"><em>{{ lang._('No volumes found') }}</em></td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Networks Tab -->
    <div id="tab-networks" class="tab-pane fade">
        <div class="table-responsive">
            <table class="table table-striped table-condensed table-hover" id="grid-networks" style="margin-bottom: 0;">
                <thead>
                    <tr>
                        <th>{{ lang._('Network Name') }}</th>
                        <th style="width: 140px;">{{ lang._('Network ID') }}</th>
                        <th style="width: 120px;">{{ lang._('Driver') }}</th>
                        <th>{{ lang._('Subnets') }}</th>
                        <th style="width: 80px;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="5" class="text-center"><em>{{ lang._('No networks found') }}</em></td></tr>
                </tbody>
            </table>
        </div>
    </div>
</div>

<!-- Container Logs Modal -->
<div class="modal fade" id="modal-logs" tabindex="-1" role="dialog" aria-labelledby="modal-logs-title" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                <h4 class="modal-title" id="modal-logs-title">{{ lang._('Container Logs') }}</h4>
            </div>
            <div class="modal-body" style="padding: 10px;">
                <pre id="modal-logs-body" style="background: #1e1e1e; color: #d4d4d4; font-family: monospace; font-size: 12px; max-height: 450px; overflow-y: auto; padding: 15px; border-radius: 4px; margin-bottom: 0; white-space: pre-wrap;"></pre>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" id="btn_refresh_modal_logs"><i class="fa fa-refresh"></i> {{ lang._('Refresh') }}</button>
                <button type="button" class="btn btn-primary" data-dismiss="modal">{{ lang._('Close') }}</button>
            </div>
        </div>
    </div>
</div>

<!-- Container Inspect Modal -->
<div class="modal fade" id="modal-inspect" tabindex="-1" role="dialog" aria-labelledby="modal-inspect-title" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                <h4 class="modal-title" id="modal-inspect-title">{{ lang._('Container Inspection') }}</h4>
            </div>
            <div class="modal-body" style="padding: 10px;">
                <pre id="modal-inspect-body" style="background: #1e1e1e; color: #d4d4d4; font-family: monospace; font-size: 12px; max-height: 450px; overflow-y: auto; padding: 15px; border-radius: 4px; margin-bottom: 0; white-space: pre-wrap;"></pre>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-primary" data-dismiss="modal">{{ lang._('Close') }}</button>
            </div>
        </div>
    </div>
</div>

<!-- Container CLI Modal -->
<div class="modal fade" id="modal-cli" tabindex="-1" role="dialog" aria-labelledby="modal-cli-title" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header" style="display: flex; justify-content: space-between; align-items: center;">
                <h4 class="modal-title" id="modal-cli-title" style="margin: 0;">{{ lang._('Container CLI') }}</h4>
                <div style="display: flex; align-items: center; gap: 10px;">
                    <div style="display: inline-flex; align-items: center; gap: 5px;">
                        <label for="cli-shell" style="margin: 0; font-size: 12px; font-weight: normal;">{{ lang._('Shell') }}:</label>
                        <input type="text" class="form-control input-sm" id="cli-shell" value="/bin/sh" style="width: 100px; display: inline-block; height: 26px;" />
                    </div>
                    <button type="button" class="btn btn-xs btn-default" id="btn_clear_cli" title="{{ lang._('Clear Console') }}"><i class="fa fa-eraser"></i> {{ lang._('Clear') }}</button>
                    <button type="button" class="close" data-dismiss="modal" aria-label="Close" style="margin-left: 10px;"><span aria-hidden="true">&times;</span></button>
                </div>
            </div>
            <div class="modal-body" style="padding: 0; background: #121212; border-radius: 0 0 6px 6px;">
                <pre id="modal-cli-console" style="background: #121212; color: #5af78e; font-family: monospace; font-size: 13px; max-height: 420px; min-height: 280px; overflow-y: auto; padding: 15px; border-radius: 0; margin-bottom: 0; border: none; white-space: pre-wrap;"></pre>
                <div style="padding: 10px; background: #1a1a1a; border-top: 1px solid #333; border-radius: 0 0 6px 6px;">
                    <div class="input-group">
                        <span class="input-group-addon" style="background: #222; color: #5af78e; border-color: #444; font-family: monospace;"><b>$</b></span>
                        <input type="text" class="form-control" id="cli-cmd-input" placeholder="{{ lang._('Type command (e.g. ping 1.1.1.1, ls -la, ps aux) and press Enter...') }}" style="background: #2a2a2a; color: #fff; border-color: #444; font-family: monospace;" />
                        <span class="input-group-btn">
                            <button class="btn btn-success" type="button" id="btn-cli-run">
                                <i class="fa fa-play" id="btn-cli-run-icon"></i> {{ lang._('Run') }}
                            </button>
                            <button class="btn btn-danger" type="button" id="btn-cli-stop" style="display: none;">
                                <i class="fa fa-stop"></i> {{ lang._('Stop') }}
                            </button>
                        </span>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
