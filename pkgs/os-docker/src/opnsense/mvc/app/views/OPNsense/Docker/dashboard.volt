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

<link rel="stylesheet" href="{{ cache_safe('/ui/css/vendor/docker/xterm.css') }}">
<script src="{{ cache_safe('/ui/js/vendor/docker/xterm.js') }}"></script>
<script src="{{ cache_safe('/ui/js/vendor/docker/addon-fit.js') }}"></script>

<style>
.modal-title > i,
.modal-title > span.fa,
.modal-title > .fa {
    margin-right: 10px;
}
</style>

<script>
    var autoRefreshInterval = null;
    var currentLogContainerId = null;
    var currentCliContainerId = null;
    var currentCliContainerName = null;
    var currentTerm = null;
    var currentFitAddon = null;
    var currentWs = null;

    function decodeHtmlEntities(str) {
        if (!str || typeof str !== 'string' || str.indexOf('&') === -1) return str;
        return str
            .replace(/&amp;/g, '&')
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"')
            .replace(/&#039;/g, "'")
            .replace(/&#39;/g, "'");
    }

    function ansiToHtml(str) {
        if (!str) return '';
        var html = decodeHtmlEntities(String(str))
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
        loadConflicts();
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
        ajaxGet('/api/docker/system/df', {}, function (data, status) {
            if (data && Array.isArray(data.items)) {
                var totalContainers = 0;
                var activeContainers = 0;
                var totalImages = 0;
                var activeImages = 0;
                var totalVolumes = 0;
                var totalNetworks = 0;
                var reclaimableStr = '0B';

                $.each(data.items, function (idx, item) {
                    var total = item.Total || item.TotalCount || 0;
                    var active = item.Active || 0;
                    if (item.Type === 'Containers') {
                        totalContainers = total;
                        activeContainers = active;
                    } else if (item.Type === 'Images') {
                        totalImages = total;
                        activeImages = active;
                        if (item.Reclaimable) {
                            reclaimableStr = item.Reclaimable;
                        }
                    } else if (item.Type === 'Local Volumes' || item.Type === 'Volumes') {
                        totalVolumes = total;
                    } else if (item.Type === 'Networks') {
                        totalNetworks = total;
                    }
                });

                reclaimableStr = reclaimableStr.replace(/(\d+\.\d+)\s*([a-zA-Z]+)/g, function (match, num, unit) {
                    return parseFloat(num).toFixed(1) + unit;
                });

                $('#stat-containers').text(activeContainers + ' / ' + totalContainers + ' Running');
                $('#stat-images').text(activeImages + ' / ' + totalImages + ' Active');
                $('#stat-volumes').text(totalVolumes + ' Volumes');
                $('#stat-reclaimable').text(reclaimableStr);

                if (totalNetworks > 0) {
                    $('#stat-networks').text(totalNetworks + ' Networks');
                } else {
                    ajaxGet('/api/docker/networks/list', {}, function (netData) {
                        if (netData && Array.isArray(netData.items)) {
                            $('#stat-networks').text(netData.items.length + ' Networks');
                        }
                    });
                }
            }
        });
    }

    function loadConflicts() {
        ajaxGet('/api/docker/system/conflicts', {}, function (data, status) {
            if (data && Array.isArray(data.conflicts) && data.conflicts.length > 0) {
                var listHtml = '';
                $.each(data.conflicts, function(idx, conf) {
                    listHtml += '<li><strong>' + $('<div>').text(conf.container || 'Container').html() + '</strong>: ' +
                                'Port <code>' + conf.host_port + '/' + conf.proto + '</code> conflicts with host service <code>' +
                                $('<div>').text(conf.process || 'unknown').html() + '</code></li>';
                });
                $('#conflict-list').html(listHtml);
                $('#docker-conflict-banner').slideDown();
            } else {
                $('#docker-conflict-banner').slideUp();
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
        return '<span title="' + iso + '">' + rel + '</span>';
    }

    function loadContainers() {
        ajaxGet('/api/docker/containers/list', {}, function (data, status) {
            var $tbody = $('#grid-containers tbody');
            var items = (data && data.items) ? data.items : [];
            cachedContainers = items;
            if (items.length === 0) {
                $tbody.html('<tr><td colspan="6" class="text-center"><em>{{ lang._("No containers found") }}</em></td></tr>');
                return;
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

                var startStopBtn = isRunning
                    ? '<button class="btn btn-xs btn-default act-stop" data-id="' + cid + '" title="{{ lang._("Stop Container") }}"><i class="fa fa-stop text-warning"></i></button> '
                    : '<button class="btn btn-xs btn-default act-start" data-id="' + cid + '" title="{{ lang._("Start Container") }}"><i class="fa fa-play text-success"></i></button> ';

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

                var deleteBtn = isRunning
                    ? '<button class="btn btn-xs btn-default" disabled="disabled" title="{{ lang._("Cannot delete running container. Stop container first.") }}"><i class="fa fa-lock text-muted"></i></button>'
                    : '<button class="btn btn-xs btn-default act-delete-container" data-id="' + cid + '" data-name="' + $('<div>').text(names).html() + '" title="{{ lang._("Delete Container") }}"><i class="fa fa-trash text-danger"></i></button>';

                var actions = startStopBtn + restartBtn + killBtn + cliBtn + logsBtn + inspectBtn + deleteBtn;

                rows += '<tr>' +
                    '<td><code>' + cid + '</code></td>' +
                    '<td><strong>' + $('<div>').text(names).html() + '</strong></td>' +
                    '<td>' + $('<div>').text(image).html() + '</td>' +
                    '<td><span class="label ' + badgeClass + '">' + $('<div>').text(state).html() + '</span></td>' +
                    '<td>' + formatTimestamp(created) + '</td>' +
                    '<td>' + actions + '</td>' +
                    '</tr>';
            });
            $tbody.html(rows);
        });
    }

    function loadImages() {
        ajaxGet('/api/docker/images/list', {}, function (data, status) {
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
        ajaxGet('/api/docker/volumes/list', {}, function (data, status) {
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
        ajaxGet('/api/docker/networks/list', {}, function (data, status) {
            var $tbody = $('#grid-networks tbody');
            var items = (data && data.items) ? data.items : [];
            $('#stat-networks').text(items.length + ' Networks');
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
                } else if (net.Scope) {
                    subnets = net.Scope;
                }
                var isDefault = (netName === 'bridge' || netName === 'none' || netName === 'host');
                var actions = '';
                if (!isDefault) {
                    actions = '<button class="btn btn-xs btn-default act-delete-network" data-name="' + $('<div>').text(netName).html() + '" title="{{ lang._("Delete Network") }}"><i class="fa fa-trash text-danger"></i></button>';
                } else {
                    actions = '<button class="btn btn-xs btn-default" disabled="disabled" title="{{ lang._("Default system network cannot be deleted") }}"><i class="fa fa-lock text-muted"></i></button>';
                }

                rows += '<tr>' +
                    '<td><strong>' + $('<div>').text(netName).html() + '</strong></td>' +
                    '<td><code>' + ((net.id || net.ID || net.Id || '').substring(0, 12) || '--') + '</code></td>' +
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
        $('#modal-logs-title').html('<i class="fa fa-file-text-o text-primary" style="margin-right: 10px;"></i>{{ lang._("Container Logs") }}: ' + $('<div>').text(name || cid).html());
        $('#modal-logs-body').text('{{ lang._("Loading logs...") }}');
        $('#modal-logs').modal('show');
        fetchLogsContent();
    }

    function fetchLogsContent() {
        if (!currentLogContainerId) return;
        ajaxGet('/api/docker/containers/logs/' + currentLogContainerId, {}, function (data, status) {
            var text = (data && data.output) ? data.output : (data && data.message ? data.message : '({{ lang._("No log output") }})');
            $('#modal-logs-body').html(ansiToHtml(text));
            var pre = document.getElementById('modal-logs-body');
            if (pre) pre.scrollTop = pre.scrollHeight;
        });
    }

    function connectTerminalWs(cid, shell, reset) {
        var host = window.location.host;
        var proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        var activeShell = shell || $('#cli-shell').val() || '/bin/sh';
        var url = proto + '//' + host + '/api/docker/terminal/ws?id=' + encodeURIComponent(cid) + '&shell=' + encodeURIComponent(activeShell);

        if (currentWs) {
            try { currentWs.close(); } catch(e) {}
            currentWs = null;
        }

        currentWs = new WebSocket(url);
        currentWs.binaryType = 'arraybuffer';

        currentWs.onopen = function () {
            if (reset && currentTerm) currentTerm.reset();
            if (currentFitAddon) currentFitAddon.fit();
            if (currentTerm && currentWs && currentWs.readyState === WebSocket.OPEN) {
                var initMsg = JSON.stringify({ type: 'resize', cols: currentTerm.cols, rows: currentTerm.rows });
                currentWs.send(initMsg);
            }
        };

        currentWs.onmessage = function (evt) {
            if (currentTerm) {
                if (typeof evt.data === 'string') {
                    currentTerm.write(evt.data);
                } else {
                    currentTerm.write(new Uint8Array(evt.data));
                }
            }
        };

        currentWs.onclose = function () {
            if (currentTerm) currentTerm.write('\r\n\x1b[33m[Connection closed]\x1b[0m\r\n');
        };
    }

    function showContainerCli(cid, name) {
        currentCliContainerId = cid;
        currentCliContainerName = name || cid;
        $('#modal-cli-title').html('<i class="fa fa-terminal text-primary" style="margin-right: 10px;"></i>{{ lang._("Container Terminal") }}: ' + $('<div>').text(currentCliContainerName).html());
        $('#modal-cli').modal('show');

        setTimeout(function () {
            var container = document.getElementById('xterm-cli-container');
            if (!container) return;
            if (!currentTerm) {
                currentTerm = new Terminal({
                    cursorBlink: true,
                    fontSize: 13,
                    fontFamily: 'Menlo, Monaco, "Courier New", monospace',
                    theme: {
                        background: '#181818',
                        foreground: '#dcdfe4',
                        cursor: '#528bff'
                    }
                });
                currentFitAddon = new FitAddon.FitAddon();
                currentTerm.loadAddon(currentFitAddon);
                currentTerm.open(container);

                currentTerm.onData(function (data) {
                    if (currentWs && currentWs.readyState === WebSocket.OPEN) {
                        currentWs.send(data);
                    }
                });

                $(window).off('resize.docker_term').on('resize.docker_term', function () {
                    if (currentFitAddon && currentTerm) {
                        currentFitAddon.fit();
                        if (currentWs && currentWs.readyState === WebSocket.OPEN) {
                            currentWs.send(JSON.stringify({
                                action: 'resize',
                                cols: currentTerm.cols,
                                rows: currentTerm.rows
                            }));
                        }
                    }
                });
            }
            if (currentFitAddon) currentFitAddon.fit();
            var shell = $('#cli-shell').val() || '/bin/sh';
            connectTerminalWs(cid, shell, true);
        }, 200);
    }

    function inspectContainer(cid, name) {
        ajaxGet('/api/docker/containers/inspect/' + cid, {}, function (data, status) {
            var raw = (data && data.output) ? data.output : (data && data.items ? JSON.stringify(data.items, null, 2) : '');
            $('#modal-inspect-title').html('<i class="fa fa-info-circle text-info" style="margin-right: 10px;"></i>{{ lang._("Inspect Container") }}: ' + $('<div>').text(name || cid).html());
            $('#inspect-raw-content').text(raw);
            $('#modal-inspect').modal('show');
        });
    }

    $(document).ready(function () {
        refreshActiveTab();
        updateServiceControlUI('docker');

        autoRefreshInterval = setInterval(function () {
            refreshActiveTab();
        }, 10000);

        $('#maintabs a').on('shown.bs.tab', function () {
            refreshActiveTab();
        });

        $('#btn_refresh_grid').click(function () {
            refreshActiveTab();
        });

        $('#btn_clear_cli').click(function () {
            if (currentTerm) {
                currentTerm.clear();
                currentTerm.focus();
            }
        });

        $('#cli-shell').change(function () {
            var shell = $(this).val() || '/bin/sh';
            if (currentCliContainerId) {
                connectTerminalWs(currentCliContainerId, shell, true);
            }
        });

        $('#modal-cli').on('hidden.bs.modal', function () {
            $(window).off('resize.docker_term');
            if (currentWs) {
                try { currentWs.close(); } catch (e) {}
                currentWs = null;
            }
        });

        $('#btn_system_prune').click(function () {
            BootstrapDialog.confirm({
                title: "{{ lang._('Prune System Resources') }}",
                message: "{{ lang._('This will remove all stopped containers, unused networks, dangling images, and build caches. Continue?') }}",
                type: BootstrapDialog.TYPE_WARNING,
                btnCancelLabel: "{{ lang._('Cancel') }}",
                btnOKLabel: "{{ lang._('Prune') }}",
                btnOKClass: "btn-warning",
                callback: function (result) {
                    if (result) {
                        $('#btn_system_prune_progress').addClass('fa fa-spinner fa-pulse');
                        ajaxCall('/api/docker/system/prune', {}, function () {
                            $('#btn_system_prune_progress').removeClass('fa fa-spinner fa-pulse');
                            refreshActiveTab();
                        }, false, function () {
                            $('#btn_system_prune_progress').removeClass('fa fa-spinner fa-pulse');
                        });
                    }
                }
            });
        });

        // Grid Action Delegation
        $(document).on('click', '.act-start', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/docker/containers/start/' + cid, {}, function () { refreshActiveTab(); });
        });

        $(document).on('click', '.act-stop', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/docker/containers/stop/' + cid, {}, function () { refreshActiveTab(); });
        });

        $(document).on('click', '.act-restart', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/docker/containers/restart/' + cid, {}, function () { refreshActiveTab(); });
        });

        $(document).on('click', '.act-kill', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/docker/containers/kill/' + cid, {}, function () { refreshActiveTab(); });
        });

        $(document).on('click', '.act-cli', function () {
            showContainerCli($(this).data('id'), $(this).data('name'));
        });

        $(document).on('click', '.act-logs', function () {
            showContainerLogs($(this).data('id'), $(this).data('name'));
        });

        $(document).on('click', '.act-inspect', function () {
            inspectContainer($(this).data('id'), $(this).data('name'));
        });

        $(document).on('click', '.act-delete-container', function () {
            var cid = $(this).data('id');
            var cname = $(this).data('name') || cid;
            BootstrapDialog.confirm({
                title: "{{ lang._('Delete Container') }}",
                message: "{{ lang._('Are you sure you want to permanently delete container: ') }}<strong>" + $('<div>').text(cname).html() + "</strong>?",
                type: BootstrapDialog.TYPE_DANGER,
                btnCancelLabel: "{{ lang._('Cancel') }}",
                btnOKLabel: "{{ lang._('Delete') }}",
                btnOKClass: "btn-danger",
                callback: function (result) {
                    if (result) {
                        ajaxCall('/api/docker/containers/delete/' + cid, {}, function () { refreshActiveTab(); });
                    }
                }
            });
        });

        $(document).on('click', '.act-delete-image', function () {
            var iid = $(this).data('id');
            var iname = $(this).data('name') || iid;
            BootstrapDialog.confirm({
                title: "{{ lang._('Delete Image') }}",
                message: "{{ lang._('Are you sure you want to delete image: ') }}<strong>" + $('<div>').text(iname).html() + "</strong>?",
                type: BootstrapDialog.TYPE_DANGER,
                btnCancelLabel: "{{ lang._('Cancel') }}",
                btnOKLabel: "{{ lang._('Delete') }}",
                btnOKClass: "btn-danger",
                callback: function (result) {
                    if (result) {
                        ajaxCall('/api/docker/images/delete/' + iid, {}, function () { refreshActiveTab(); });
                    }
                }
            });
        });

        $(document).on('click', '.act-delete-volume', function () {
            var vname = $(this).data('name');
            BootstrapDialog.confirm({
                title: "{{ lang._('Delete Volume') }}",
                message: "{{ lang._('Are you sure you want to delete volume: ') }}<strong>" + $('<div>').text(vname).html() + "</strong>?",
                type: BootstrapDialog.TYPE_DANGER,
                btnCancelLabel: "{{ lang._('Cancel') }}",
                btnOKLabel: "{{ lang._('Delete') }}",
                btnOKClass: "btn-danger",
                callback: function (result) {
                    if (result) {
                        ajaxCall('/api/docker/volumes/delete/' + vname, {}, function () { refreshActiveTab(); });
                    }
                }
            });
        });

        $(document).on('click', '.act-delete-network', function () {
            var netName = $(this).data('name');
            BootstrapDialog.confirm({
                title: "{{ lang._('Delete Network') }}",
                message: "{{ lang._('Are you sure you want to delete network: ') }}<strong>" + $('<div>').text(netName).html() + "</strong>?",
                type: BootstrapDialog.TYPE_DANGER,
                btnCancelLabel: "{{ lang._('Cancel') }}",
                btnOKLabel: "{{ lang._('Delete') }}",
                btnOKClass: "btn-danger",
                callback: function (result) {
                    if (result) {
                        ajaxCall('/api/docker/networks/delete/' + netName, {}, function () { refreshActiveTab(); });
                    }
                }
            });
        });

        $('#modal-cli').on('hidden.bs.modal', function () {
            if (currentWs) {
                try { currentWs.close(); } catch(e) {}
                currentWs = null;
            }
        });
    });
</script>

<!-- Conflict Alert Banner -->
<div id="docker-conflict-banner" class="alert alert-danger" style="display: none; margin-bottom: 20px;">
    <h4><i class="fa fa-exclamation-triangle"></i> <b>{{ lang._('Docker Port Conflicts Detected!') }}</b></h4>
    <p>{{ lang._('The following published container ports conflict with services running on the OPNsense firewall:') }}</p>
    <ul id="conflict-list" style="margin-bottom: 10px;"></ul>
    <p>{{ lang._('Port forwarding for these containers has been blocked to prevent firewall service disruption.') }}</p>
</div>

<!-- System Overview Stats Bar -->
<div class="row" style="margin-bottom: 20px;">
    <div class="col-md-2 col-sm-4 col-xs-6">
        <div class="panel panel-default" style="margin-bottom: 0;">
            <div class="panel-body" style="padding: 12px; display: flex; align-items: center; min-height: 70px;">
                <i class="fa fa-cubes fa-2x text-primary" style="margin-right: 12px;"></i>
                <div style="text-align: left;">
                    <div class="text-muted" style="font-size: 11px; text-transform: uppercase; font-weight: 600;">{{ lang._('Containers') }}</div>
                    <div id="stat-containers" style="font-size: 14px; font-weight: 700;">--</div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-2 col-sm-4 col-xs-6">
        <div class="panel panel-default" style="margin-bottom: 0;">
            <div class="panel-body" style="padding: 12px; display: flex; align-items: center; min-height: 70px;">
                <i class="fa fa-clone fa-2x text-info" style="margin-right: 12px;"></i>
                <div style="text-align: left;">
                    <div class="text-muted" style="font-size: 11px; text-transform: uppercase; font-weight: 600;">{{ lang._('Images') }}</div>
                    <div id="stat-images" style="font-size: 14px; font-weight: 700;">--</div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-2 col-sm-4 col-xs-6">
        <div class="panel panel-default" style="margin-bottom: 0;">
            <div class="panel-body" style="padding: 12px; display: flex; align-items: center; min-height: 70px;">
                <i class="fa fa-database fa-2x text-warning" style="margin-right: 12px;"></i>
                <div style="text-align: left;">
                    <div class="text-muted" style="font-size: 11px; text-transform: uppercase; font-weight: 600;">{{ lang._('Volumes') }}</div>
                    <div id="stat-volumes" style="font-size: 14px; font-weight: 700;">--</div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-2 col-sm-4 col-xs-6">
        <div class="panel panel-default" style="margin-bottom: 0;">
            <div class="panel-body" style="padding: 12px; display: flex; align-items: center; min-height: 70px;">
                <i class="fa fa-sitemap fa-2x text-success" style="margin-right: 12px;"></i>
                <div style="text-align: left;">
                    <div class="text-muted" style="font-size: 11px; text-transform: uppercase; font-weight: 600;">{{ lang._('Networks') }}</div>
                    <div id="stat-networks" style="font-size: 14px; font-weight: 700;">--</div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-4 col-sm-8 col-xs-12">
        <div class="panel panel-default" style="margin-bottom: 0;">
            <div class="panel-body" style="padding: 12px; display: flex; align-items: center; min-height: 70px;">
                <i class="fa fa-recycle fa-2x text-muted" style="margin-right: 12px;"></i>
                <div style="text-align: left;">
                    <div class="text-muted" style="font-size: 11px; text-transform: uppercase; font-weight: 600;">{{ lang._('Reclaimable') }}</div>
                    <div id="stat-reclaimable" style="font-size: 14px; font-weight: 700;">--</div>
                </div>
                <button id="btn_system_prune" class="btn btn-xs btn-warning" style="margin-left: auto;" title="{{ lang._('Prune unused containers and images') }}">
                    <i class="fa fa-trash-o"></i> {{ lang._('Prune') }} <i id="btn_system_prune_progress"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- Navigation Tabs -->
<ul class="nav nav-tabs" role="tablist" id="maintabs" style="margin-bottom: 0;">
    <li class="active"><a href="#tab-containers" data-toggle="tab"><i class="fa fa-cubes"></i> <b>{{ lang._('Containers') }}</b></a></li>
    <li><a href="#tab-images" data-toggle="tab"><i class="fa fa-clone"></i> <b>{{ lang._('Images') }}</b></a></li>
    <li><a href="#tab-volumes" data-toggle="tab"><i class="fa fa-database"></i> <b>{{ lang._('Volumes') }}</b></a></li>
    <li><a href="#tab-networks" data-toggle="tab"><i class="fa fa-sitemap"></i> <b>{{ lang._('Networks') }}</b></a></li>
    <li class="pull-right">
        <button id="btn_refresh_grid" class="btn btn-sm btn-default" style="margin-top: 5px; margin-right: 5px;" title="{{ lang._('Refresh View') }}">
            <i class="fa fa-refresh"></i> {{ lang._('Refresh') }}
        </button>
    </li>
</ul>

<!-- Tab Panes -->
<div class="content-box tab-content" style="padding: 0; border-top: none;">
    <!-- Containers Pane -->
    <div id="tab-containers" class="tab-pane active" style="padding: 15px;">
        <div class="table-responsive">
            <table class="table table-striped table-hover" id="grid-containers">
                <thead>
                    <tr>
                        <th style="width: 120px;">{{ lang._('ID') }}</th>
                        <th>{{ lang._('Name') }}</th>
                        <th>{{ lang._('Image') }}</th>
                        <th style="width: 120px;">{{ lang._('Status') }}</th>
                        <th style="width: 150px;">{{ lang._('Created') }}</th>
                        <th style="width: 200px;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="6" class="text-center"><i class="fa fa-spinner fa-pulse"></i> {{ lang._('Loading containers...') }}</td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Images Pane -->
    <div id="tab-images" class="tab-pane" style="padding: 15px;">
        <div class="table-responsive">
            <table class="table table-striped table-hover" id="grid-images">
                <thead>
                    <tr>
                        <th>{{ lang._('Repository:Tag') }}</th>
                        <th style="width: 140px;">{{ lang._('Image ID') }}</th>
                        <th style="width: 120px;">{{ lang._('Size') }}</th>
                        <th style="width: 150px;">{{ lang._('Created') }}</th>
                        <th style="width: 100px;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="5" class="text-center"><i class="fa fa-spinner fa-pulse"></i> {{ lang._('Loading images...') }}</td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Volumes Pane -->
    <div id="tab-volumes" class="tab-pane" style="padding: 15px;">
        <div class="table-responsive">
            <table class="table table-striped table-hover" id="grid-volumes">
                <thead>
                    <tr>
                        <th>{{ lang._('Name') }}</th>
                        <th style="width: 140px;">{{ lang._('Driver') }}</th>
                        <th>{{ lang._('Mountpoint') }}</th>
                        <th style="width: 100px;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="4" class="text-center"><i class="fa fa-spinner fa-pulse"></i> {{ lang._('Loading volumes...') }}</td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Networks Pane -->
    <div id="tab-networks" class="tab-pane" style="padding: 15px;">
        <div class="table-responsive">
            <table class="table table-striped table-hover" id="grid-networks">
                <thead>
                    <tr>
                        <th>{{ lang._('Name') }}</th>
                        <th style="width: 140px;">{{ lang._('Network ID') }}</th>
                        <th style="width: 140px;">{{ lang._('Driver') }}</th>
                        <th>{{ lang._('Subnets / Gateway') }}</th>
                        <th style="width: 100px;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="5" class="text-center"><i class="fa fa-spinner fa-pulse"></i> {{ lang._('Loading networks...') }}</td></tr>
                </tbody>
            </table>
        </div>
    </div>
</div>

<!-- Modal: Container Logs -->
<div class="modal fade" id="modal-logs" tabindex="-1" role="dialog">
    <div class="modal-dialog modal-lg" style="width: 80%;">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title" id="modal-logs-title"><i class="fa fa-file-text-o text-primary"></i> {{ lang._('Container Logs') }}</h4>
            </div>
            <div class="modal-body" style="padding: 0;">
                <pre id="modal-logs-body" style="background: #1c1f24; color: #dcdfe4; padding: 15px; margin: 0; min-height: 400px; max-height: 600px; overflow-y: auto; font-family: Menlo, Monaco, 'Courier New', monospace; font-size: 12px; border-radius: 0;"></pre>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default pull-left" onclick="fetchLogsContent()"><i class="fa fa-refresh"></i> {{ lang._('Refresh') }}</button>
                <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Close') }}</button>
            </div>
        </div>
    </div>
</div>

<!-- Modal: Container CLI (XTerm.js) -->
<div class="modal fade" id="modal-cli" tabindex="-1" role="dialog" aria-labelledby="modal-cli-title" aria-hidden="true">
    <div class="modal-dialog modal-lg" style="width: 85%; max-width: 1200px; margin: 75px auto 30px auto;" role="document">
        <div class="modal-content">
            <div class="modal-header" style="display: flex; justify-content: space-between; align-items: center; padding: 10px 15px;">
                <h4 class="modal-title" id="modal-cli-title" style="margin: 0;">
                    <i class="fa fa-terminal text-primary" style="margin-right: 10px;"></i>{{ lang._('Container Terminal') }}
                </h4>
                <div style="display: flex; align-items: center; gap: 8px; margin-right: 20px;">
                    <div style="display: inline-flex; align-items: center; gap: 5px;">
                        <label for="cli-shell" style="margin: 0; font-size: 12px; font-weight: normal;">{{ lang._('Shell') }}:</label>
                        <input type="text" class="form-control input-sm" id="cli-shell" list="cli-shell-list" value="/bin/sh" style="width: 110px; height: 26px; padding: 2px 8px;" />
                        <datalist id="cli-shell-list">
                            <option value="/bin/sh">
                            <option value="/bin/bash">
                            <option value="/bin/csh">
                            <option value="/bin/zsh">
                            <option value="/bin/ash">
                        </datalist>
                    </div>
                    <button type="button" class="btn btn-xs btn-default" id="btn_clear_cli" title="{{ lang._('Clear Terminal') }}"><i class="fa fa-eraser"></i> {{ lang._('Clear') }}</button>
                </div>
                <button type="button" class="close" data-dismiss="modal" aria-label="Close" style="margin-top: -2px;"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body" style="padding: 15px; background: #181818; border-radius: 0 0 4px 4px;">
                <div id="xterm-cli-container" style="height: 480px; min-height: 400px; width: 100%; padding: 8px; border-radius: 4px; background: #181818;"></div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-primary" data-dismiss="modal">{{ lang._('Close') }}</button>
            </div>
        </div>
    </div>
</div>

<!-- Modal: Inspect Container -->
<div class="modal fade" id="modal-inspect" tabindex="-1" role="dialog">
    <div class="modal-dialog modal-lg" style="width: 80%;">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title" id="modal-inspect-title"><i class="fa fa-info-circle text-info"></i> {{ lang._('Inspect') }}</h4>
            </div>
            <div class="modal-body" style="padding: 0;">
                <pre id="inspect-raw-content" style="background: #f5f5f5; color: #333; padding: 15px; margin: 0; min-height: 400px; max-height: 600px; overflow-y: auto; font-family: Menlo, Monaco, 'Courier New', monospace; font-size: 12px; border-radius: 0;"></pre>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Close') }}</button>
            </div>
        </div>
    </div>
</div>
