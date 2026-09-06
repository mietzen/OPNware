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

<link rel="stylesheet" href="{{ cache_safe('/ui/css/vendor/xterm/xterm.css') }}">
<script src="{{ cache_safe('/ui/js/vendor/xterm/xterm.js') }}"></script>
<script src="{{ cache_safe('/ui/js/vendor/xterm/addon-fit.js') }}"></script>

<script>
    var autoRefreshInterval = null;
    var currentLogContainerId = null;
    var currentCliContainerId = null;
    var currentCliContainerName = null;
    var currentTerm = null;
    var currentFitAddon = null;
    var currentWs = null;

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
        return '<span title="' + iso + '">' + rel + '</span>';
    }

    function loadContainers() {
        ajaxGet('/api/podman/containers/list', {}, function (data, status) {
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
                    '<td>' + formatTimestamp(created) + '</td>' +
                    '<td>' + actions + '</td>' +
                    '</tr>';
            });
            $tbody.html(rows);
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

    var currentInspectRaw = null;
    var currentInspectView = 'json';

    function escapeHtml(str) {
        if (str === null || str === undefined) {
            return '';
        }
        return $('<div>').text(String(str)).html();
    }

    function copyToClipboard(text, btnElement) {
        if (!text) {
            return;
        }

        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(function () {
                showCopyFeedback(btnElement);
            });
            return;
        }

        var textArea = document.createElement("textarea");
        textArea.value = text;
        textArea.style.position = "fixed";
        textArea.style.left = "-999999px";
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();

        try {
            document.execCommand('copy');
            showCopyFeedback(btnElement);
        } catch (err) {}

        document.body.removeChild(textArea);
    }

    function showCopyFeedback(btnElement) {
        if (!btnElement) {
            return;
        }

        var $btn = $(btnElement);
        var origHtml = $btn.html();
        $btn.html('<i class="fa fa-check text-success"></i>');

        setTimeout(function () {
            $btn.html(origHtml);
        }, 1500);
    }

    function jsonToYaml(data, indentLevel) {
        indentLevel = indentLevel || 0;
        var indent = '  '.repeat(indentLevel);

        if (data === null) {
            return 'null\n';
        }
        if (data === undefined) {
            return '\n';
        }
        if (typeof data === 'boolean' || typeof data === 'number') {
            return data + '\n';
        }
        if (typeof data === 'string') {
            if (data.indexOf('\n') !== -1 || /[:#\[\]{},&*?|<>=!%@`]/.test(data) || data === '' || /^(true|false|null|yes|no)$/i.test(data) || !isNaN(Number(data))) {
                return JSON.stringify(data) + '\n';
            }
            return data + '\n';
        }
        if (Array.isArray(data)) {
            if (data.length === 0) {
                return '[]\n';
            }
            var str = '\n';
            if (indentLevel === 0) {
                str = '';
            }
            for (var i = 0; i < data.length; i++) {
                var val = data[i];
                if (typeof val === 'object' && val !== null) {
                    var inner = jsonToYaml(val, indentLevel + 1);
                    var trimmed = inner.replace(/^\s+/, '');
                    str += indent + '- ' + trimmed;
                } else {
                    str += indent + '- ' + jsonToYaml(val, 0);
                }
            }
            return str;
        }
        if (typeof data === 'object') {
            var keys = Object.keys(data);
            if (keys.length === 0) {
                return '{}\n';
            }
            var str = '\n';
            if (indentLevel === 0) {
                str = '';
            }
            for (var j = 0; j < keys.length; j++) {
                var key = keys[j];
                var val = data[key];
                var keyStr = /^[a-zA-Z0-9_\-\.]+$/.test(key) ? key : JSON.stringify(key);
                if (typeof val === 'object' && val !== null) {
                    if (Array.isArray(val)) {
                        if (val.length === 0) {
                            str += indent + keyStr + ': []\n';
                        } else {
                            str += indent + keyStr + ':' + jsonToYaml(val, indentLevel + 1);
                        }
                    } else {
                        if (Object.keys(val).length === 0) {
                            str += indent + keyStr + ': {}\n';
                        } else {
                            str += indent + keyStr + ':' + jsonToYaml(val, indentLevel + 1);
                        }
                    }
                } else {
                    str += indent + keyStr + ': ' + jsonToYaml(val, 0);
                }
            }
            return str;
        }
        return String(data) + '\n';
    }

    function updateInspectRawView() {
        if (!currentInspectRaw) {
            $('#modal-inspect-raw').text('');
            return;
        }
        if (currentInspectView === 'yaml') {
            $('#modal-inspect-raw').text(jsonToYaml(currentInspectRaw));
        } else {
            $('#modal-inspect-raw').text(JSON.stringify(currentInspectRaw, null, 2));
        }
    }

    function renderInspectModal(data) {
        var rawObj = data;
        if (data && data.items) {
            rawObj = Array.isArray(data.items) ? (data.items[0] || {}) : data.items;
        } else if (data && data.output && typeof data.output === 'string') {
            try {
                var parsed = JSON.parse(data.output);
                rawObj = Array.isArray(parsed) ? (parsed[0] || {}) : parsed;
            } catch (e) {
                rawObj = data.output;
            }
        } else if (Array.isArray(data)) {
            rawObj = data[0] || {};
        }

        currentInspectRaw = rawObj;

        if (typeof rawObj !== 'object' || rawObj === null) {
            $('#modal-inspect-content').html('<div class="alert alert-warning">' + escapeHtml(String(rawObj)) + '</div>');
            return;
        }

        var cname = (rawObj.Name || (Array.isArray(rawObj.Names) ? rawObj.Names.join(', ') : rawObj.Names) || '--').replace(/^\//, '');
        var fullId = rawObj.Id || rawObj.ID || rawObj.Digest || '';
        var shortId = fullId.length > 12 ? fullId.substring(0, 12) : fullId;
        var imageTag = rawObj.ImageName || (rawObj.Config && rawObj.Config.Image) || rawObj.Image || (Array.isArray(rawObj.RepoTags) ? rawObj.RepoTags.join(', ') : '--');
        var created = rawObj.Created || rawObj.CreatedAt || (rawObj.State && rawObj.State.StartedAt) || '';

        var statusBadge = '<span class="label label-default">Unknown</span>';
        var stateDetail = '';
        if (rawObj.State && typeof rawObj.State === 'object') {
            var st = (rawObj.State.Status || (rawObj.State.Running ? 'running' : 'exited')).toLowerCase();
            var badgeClass = 'label-default';
            if (st === 'running' || st === 'up') {
                badgeClass = 'label-success';
            } else if (st === 'paused') {
                badgeClass = 'label-warning';
            } else if (st === 'restarting') {
                badgeClass = 'label-info';
            } else if (st === 'exited' || st === 'dead') {
                badgeClass = (rawObj.State.ExitCode === 0) ? 'label-default' : 'label-danger';
            } else if (st === 'created') {
                badgeClass = 'label-primary';
            }
            statusBadge = '<span class="label ' + badgeClass + '">' + escapeHtml(st.toUpperCase()) + '</span>';
            if (rawObj.State.ExitCode !== undefined && st !== 'running') {
                stateDetail = ' <small class="text-muted">(' + '{{ lang._("Exit Code") }}: ' + rawObj.State.ExitCode + ')</small>';
            }
        } else if (rawObj.Status) {
            statusBadge = '<span class="label label-info">' + escapeHtml(rawObj.Status) + '</span>';
        }

        var imageDigest = rawObj.Image || '';
        var imageDigestShort = imageDigest.length > 19 ? imageDigest.substring(0, 19) + '...' : imageDigest;

        var headerHtml = '<div class="panel panel-default" style="margin-bottom: 15px;">' +
            '<div class="panel-body" style="padding: 12px 15px;">' +
            '<div class="row">' +
            '<div class="col-xs-12 col-sm-6 col-md-3">' +
            '<div class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._("Container Name") }}</div>' +
            '<div style="font-size: 16px; font-weight: bold; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;" title="' + escapeHtml(cname) + '">' + escapeHtml(cname) + '</div>' +
            '</div>' +
            '<div class="col-xs-12 col-sm-6 col-md-3">' +
            '<div class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._("ID / Digest") }}</div>' +
            '<div style="display: flex; align-items: center; gap: 6px;">' +
            '<code title="' + escapeHtml(fullId) + '">' + escapeHtml(shortId) + '</code>' +
            (fullId ? '<button type="button" class="btn btn-xs btn-default btn-copy-val" data-copy-val="' + escapeHtml(fullId) + '" title="{{ lang._("Copy full ID") }}"><i class="fa fa-clipboard"></i></button>' : '') +
            '</div>' +
            '</div>' +
            '<div class="col-xs-12 col-sm-6 col-md-3">' +
            '<div class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._("Status") }}</div>' +
            '<div>' + statusBadge + stateDetail + '</div>' +
            '</div>' +
            '<div class="col-xs-12 col-sm-6 col-md-3">' +
            '<div class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._("Created") }}</div>' +
            '<div>' + formatTimestamp(created) + '</div>' +
            '</div>' +
            '</div>' +
            '<div class="row" style="margin-top: 8px; padding-top: 8px; border-top: 1px solid #f0f0f0;">' +
            '<div class="col-xs-12">' +
            '<span class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._("Image") }}: </span>' +
            '<code>' + escapeHtml(imageTag) + '</code>' +
            (imageDigest && imageDigest !== imageTag ? ' <span class="text-muted">({{ lang._("Digest/ID") }}: <code title="' + escapeHtml(imageDigest) + '">' + escapeHtml(imageDigestShort) + '</code>)</span>' : '') +
            '</div>' +
            '</div>' +
            '</div>' +
            '</div>';

        var portsObj = (rawObj.NetworkSettings && rawObj.NetworkSettings.Ports) || (rawObj.HostConfig && rawObj.HostConfig.PortBindings) || rawObj.Ports || {};
        var portRows = '';
        if (typeof portsObj === 'object' && portsObj !== null) {
            $.each(portsObj, function (cPort, hostBindings) {
                if (Array.isArray(hostBindings) && hostBindings.length > 0) {
                    $.each(hostBindings, function (bIdx, b) {
                        var hostIp = b.HostIp || '0.0.0.0';
                        var hostPort = b.HostPort || '--';
                        portRows += '<tr><td><code>' + escapeHtml(hostIp) + ':' + escapeHtml(hostPort) + '</code></td><td style="width: 20px; text-align: center;"><i class="fa fa-arrow-right text-muted"></i></td><td><code>' + escapeHtml(cPort) + '</code></td></tr>';
                    });
                } else if (typeof hostBindings === 'string') {
                    portRows += '<tr><td><code>' + escapeHtml(hostBindings) + '</code></td><td style="width: 20px; text-align: center;"><i class="fa fa-arrow-right text-muted"></i></td><td><code>' + escapeHtml(cPort) + '</code></td></tr>';
                } else {
                    portRows += '<tr><td><span class="text-muted">--</span></td><td style="width: 20px; text-align: center;"><i class="fa fa-arrow-right text-muted"></i></td><td><code>' + escapeHtml(cPort) + '</code></td></tr>';
                }
            });
        }

        var nets = (rawObj.NetworkSettings && rawObj.NetworkSettings.Networks) || {};
        var netNames = Object.keys(nets).join(', ') || (rawObj.HostConfig && rawObj.HostConfig.NetworkMode) || 'bridge';
        var firstNet = nets[Object.keys(nets)[0]] || {};
        var ipAddr = (rawObj.NetworkSettings && rawObj.NetworkSettings.IPAddress) || firstNet.IPAddress || '--';
        var macAddr = (rawObj.NetworkSettings && rawObj.NetworkSettings.MacAddress) || firstNet.MacAddress || '--';
        var gwAddr = (rawObj.NetworkSettings && rawObj.NetworkSettings.Gateway) || firstNet.Gateway || '--';

        var networkHtml = '<div class="panel panel-default" style="height: 100%; margin-bottom: 0;">' +
            '<div class="panel-heading" style="font-weight: bold; font-size: 12px; text-transform: uppercase;"><i class="fa fa-sitemap text-primary"></i> {{ lang._("Network & Ports") }}</div>' +
            '<div class="panel-body" style="padding: 10px 15px;">' +
            '<table class="table table-condensed" style="margin-bottom: 8px;">' +
            '<tr><td style="width: 100px;" class="text-muted">{{ lang._("Network") }}</td><td><strong>' + escapeHtml(netNames) + '</strong></td></tr>' +
            '<tr><td class="text-muted">{{ lang._("IP Address") }}</td><td><code>' + escapeHtml(ipAddr) + '</code></td></tr>' +
            '<tr><td class="text-muted">{{ lang._("MAC Address") }}</td><td><code>' + escapeHtml(macAddr) + '</code></td></tr>' +
            '<tr><td class="text-muted">{{ lang._("Gateway") }}</td><td><code>' + escapeHtml(gwAddr) + '</code></td></tr>' +
            '</table>' +
            '<div class="text-muted" style="font-size: 11px; text-transform: uppercase; margin-bottom: 4px;">{{ lang._("Port Mappings") }}</div>' +
            (portRows ? '<div class="table-responsive" style="max-height: 120px; overflow-y: auto;"><table class="table table-striped table-condensed" style="margin-bottom: 0;"><thead><tr><th>Host</th><th></th><th>Container</th></tr></thead><tbody>' + portRows + '</tbody></table></div>' : '<div class="text-muted" style="font-size: 12px;"><em>{{ lang._("No port mappings") }}</em></div>') +
            '</div>' +
            '</div>';

        var mounts = rawObj.Mounts || [];
        var mountRows = '';
        if (Array.isArray(mounts) && mounts.length > 0) {
            $.each(mounts, function (mIdx, m) {
                var mType = m.Type || 'bind';
                var mSrc = m.Source || m.Name || '--';
                var mDst = m.Destination || '--';
                var mMode = m.Mode || (m.RW ? 'rw' : 'ro');
                var modeBadge = (mMode === 'ro') ? '<span class="label label-default">ro</span>' : '<span class="label label-info">rw</span>';
                mountRows += '<tr>' +
                    '<td><span class="label label-default">' + escapeHtml(mType) + '</span></td>' +
                    '<td style="word-break: break-all; max-width: 180px;"><code>' + escapeHtml(mSrc) + '</code></td>' +
                    '<td style="word-break: break-all; max-width: 180px;"><code>' + escapeHtml(mDst) + '</code></td>' +
                    '<td>' + modeBadge + '</td>' +
                    '</tr>';
            });
        } else if (rawObj.HostConfig && Array.isArray(rawObj.HostConfig.Binds) && rawObj.HostConfig.Binds.length > 0) {
            $.each(rawObj.HostConfig.Binds, function (bIdx, bindStr) {
                var parts = String(bindStr).split(':');
                var mSrc = parts[0] || '--';
                var mDst = parts[1] || '--';
                var mMode = parts[2] || 'rw';
                var modeBadge = (mMode === 'ro') ? '<span class="label label-default">ro</span>' : '<span class="label label-info">rw</span>';
                mountRows += '<tr>' +
                    '<td><span class="label label-default">bind</span></td>' +
                    '<td style="word-break: break-all; max-width: 180px;"><code>' + escapeHtml(mSrc) + '</code></td>' +
                    '<td style="word-break: break-all; max-width: 180px;"><code>' + escapeHtml(mDst) + '</code></td>' +
                    '<td>' + modeBadge + '</td>' +
                    '</tr>';
            });
        }

        var storageHtml = '<div class="panel panel-default" style="height: 100%; margin-bottom: 0;">' +
            '<div class="panel-heading" style="font-weight: bold; font-size: 12px; text-transform: uppercase;"><i class="fa fa-database text-primary"></i> {{ lang._("Storage & Mounts") }}</div>' +
            '<div class="panel-body" style="padding: 10px 15px;">' +
            (mountRows ? '<div class="table-responsive" style="max-height: 220px; overflow-y: auto;"><table class="table table-striped table-condensed" style="margin-bottom: 0;"><thead><tr><th style="width: 60px;">{{ lang._("Type") }}</th><th>{{ lang._("Source") }}</th><th>{{ lang._("Destination") }}</th><th style="width: 50px;">{{ lang._("Mode") }}</th></tr></thead><tbody>' + mountRows + '</tbody></table></div>' : '<div class="text-muted" style="padding: 20px 0; text-align: center;"><em>{{ lang._("No storage mounts configured") }}</em></div>') +
            '</div>' +
            '</div>';

        var isPriv = !!(rawObj.HostConfig && rawObj.HostConfig.Privileged);
        var privBadge = isPriv ? '<span class="label label-danger"><i class="fa fa-shield"></i> {{ lang._("Privileged") }}</span>' : '<span class="label label-success"><i class="fa fa-shield"></i> {{ lang._("Unprivileged") }}</span>';

        var capAdd = (rawObj.HostConfig && rawObj.HostConfig.CapAdd) || rawObj.CapAdd || [];
        var capDrop = (rawObj.HostConfig && rawObj.HostConfig.CapDrop) || rawObj.CapDrop || [];
        var capHtml = '';
        if (Array.isArray(capAdd) && capAdd.length > 0) {
            $.each(capAdd, function (cIdx, c) {
                capHtml += '<span class="label label-info" style="margin-right: 4px; display: inline-block; margin-bottom: 3px;">+' + escapeHtml(c) + '</span>';
            });
        }
        if (Array.isArray(capDrop) && capDrop.length > 0) {
            $.each(capDrop, function (cIdx, c) {
                capHtml += '<span class="label label-default" style="margin-right: 4px; display: inline-block; margin-bottom: 3px;">-' + escapeHtml(c) + '</span>';
            });
        }
        if (!capHtml) {
            capHtml = '<span class="text-muted"><em>{{ lang._("Default capabilities") }}</em></span>';
        }

        var restartPolicy = (rawObj.HostConfig && rawObj.HostConfig.RestartPolicy && rawObj.HostConfig.RestartPolicy.Name) || 'no';
        var restartRetries = (rawObj.HostConfig && rawObj.HostConfig.RestartPolicy && rawObj.HostConfig.RestartPolicy.MaximumRetryCount) || 0;
        var restartStr = escapeHtml(restartPolicy) + (restartRetries > 0 ? ' (' + restartRetries + ' retries)' : '');

        var memBytes = (rawObj.HostConfig && rawObj.HostConfig.Memory) || 0;
        var memStr = memBytes > 0 ? (memBytes >= 1073741824 ? (memBytes / 1073741824).toFixed(1) + ' GB' : (memBytes / 1048576).toFixed(0) + ' MB') : '{{ lang._("Unlimited") }}';

        var nanoCpus = (rawObj.HostConfig && (rawObj.HostConfig.NanoCpus || rawObj.HostConfig.NanoCPUs)) || 0;
        var cpuStr = '{{ lang._("Unlimited") }}';
        if (nanoCpus > 0) {
            cpuStr = (nanoCpus / 1e9).toFixed(2) + ' {{ lang._("CPUs") }}';
        } else if (rawObj.HostConfig && rawObj.HostConfig.CpuQuota && rawObj.HostConfig.CpuPeriod) {
            cpuStr = (rawObj.HostConfig.CpuQuota / rawObj.HostConfig.CpuPeriod).toFixed(2) + ' {{ lang._("CPUs") }}';
        }

        var securityHtml = '<div class="panel panel-default" style="height: 100%; margin-bottom: 0;">' +
            '<div class="panel-heading" style="font-weight: bold; font-size: 12px; text-transform: uppercase;"><i class="fa fa-lock text-primary"></i> {{ lang._("Security & Runtime") }}</div>' +
            '<div class="panel-body" style="padding: 10px 15px;">' +
            '<table class="table table-condensed" style="margin-bottom: 0;">' +
            '<tr><td style="width: 120px;" class="text-muted">{{ lang._("Privilege Mode") }}</td><td>' + privBadge + '</td></tr>' +
            '<tr><td class="text-muted">{{ lang._("Restart Policy") }}</td><td><code>' + restartStr + '</code></td></tr>' +
            '<tr><td class="text-muted">{{ lang._("Memory Limit") }}</td><td><code>' + memStr + '</code></td></tr>' +
            '<tr><td class="text-muted">{{ lang._("CPU Limit") }}</td><td><code>' + cpuStr + '</code></td></tr>' +
            '<tr><td class="text-muted">{{ lang._("Capabilities") }}</td><td><div style="max-height: 80px; overflow-y: auto;">' + capHtml + '</div></td></tr>' +
            '</table>' +
            '</div>' +
            '</div>';

        var workDir = (rawObj.Config && rawObj.Config.WorkingDir) || rawObj.WorkingDir || '/';
        var entrypoint = (rawObj.Config && rawObj.Config.Entrypoint) || rawObj.Entrypoint || [];
        var entrypointStr = Array.isArray(entrypoint) ? entrypoint.join(' ') : String(entrypoint);
        var cmd = (rawObj.Config && rawObj.Config.Cmd) || rawObj.Cmd || [];
        var cmdStr = Array.isArray(cmd) ? cmd.join(' ') : String(cmd);

        var envList = (rawObj.Config && rawObj.Config.Env) || rawObj.Env || [];
        var envHtml = '';
        if (Array.isArray(envList) && envList.length > 0) {
            $.each(envList, function (eIdx, envItem) {
                var eqIdx = String(envItem).indexOf('=');
                var k = eqIdx !== -1 ? String(envItem).substring(0, eqIdx) : String(envItem);
                var v = eqIdx !== -1 ? String(envItem).substring(eqIdx + 1) : '';
                envHtml += '<div class="inspect-env-item" style="padding: 3px 6px; border-bottom: 1px solid #f0f0f0; font-family: monospace; font-size: 11px; word-break: break-all;">' +
                    '<strong class="text-primary">' + escapeHtml(k) + '</strong>=' +
                    '<span class="text-muted">' + escapeHtml(v) + '</span>' +
                    '</div>';
            });
        } else {
            envHtml = '<div class="text-muted" style="padding: 8px 6px; font-size: 12px;"><em>{{ lang._("No environment variables") }}</em></div>';
        }

        var executionHtml = '<div class="panel panel-default" style="height: 100%; margin-bottom: 0;">' +
            '<div class="panel-heading" style="font-weight: bold; font-size: 12px; text-transform: uppercase;"><i class="fa fa-terminal text-primary"></i> {{ lang._("Environment & Execution") }}</div>' +
            '<div class="panel-body" style="padding: 10px 15px;">' +
            '<table class="table table-condensed" style="margin-bottom: 8px;">' +
            '<tr><td style="width: 100px;" class="text-muted">{{ lang._("Working Dir") }}</td><td><code>' + escapeHtml(workDir) + '</code></td></tr>' +
            '<tr><td class="text-muted">{{ lang._("Entrypoint") }}</td><td><code>' + (entrypointStr ? escapeHtml(entrypointStr) : '<span class="text-muted">none</span>') + '</code></td></tr>' +
            '<tr><td class="text-muted">{{ lang._("Command") }}</td><td><code>' + (cmdStr ? escapeHtml(cmdStr) : '<span class="text-muted">none</span>') + '</code></td></tr>' +
            '</table>' +
            '<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">' +
            '<span class="text-muted" style="font-size: 11px; text-transform: uppercase;">{{ lang._("Environment Variables") }} (' + (Array.isArray(envList) ? envList.length : 0) + ')</span>' +
            (Array.isArray(envList) && envList.length > 4 ? '<input type="text" id="inspect-env-filter" placeholder="{{ lang._("Filter...") }}" style="width: 110px; height: 22px; padding: 1px 6px; font-size: 11px; border: 1px solid #ccc; border-radius: 3px;" />' : '') +
            '</div>' +
            '<div id="inspect-env-list" style="max-height: 110px; overflow-y: auto; background: #fafafa; border: 1px solid #e0e0e0; border-radius: 3px;">' + envHtml + '</div>' +
            '</div>' +
            '</div>';

        var labelsObj = (rawObj.Config && rawObj.Config.Labels) || rawObj.Labels || {};
        var labelRows = '';
        if (typeof labelsObj === 'object' && labelsObj !== null) {
            $.each(labelsObj, function (lk, lv) {
                labelRows += '<tr><td style="width: 30%; word-break: break-all;"><code>' + escapeHtml(lk) + '</code></td><td style="word-break: break-all;">' + escapeHtml(lv) + '</td></tr>';
            });
        }

        var labelsHtml = '<div class="panel panel-default" style="margin-bottom: 15px;">' +
            '<div class="panel-heading" style="font-weight: bold; font-size: 12px; text-transform: uppercase;"><i class="fa fa-tags text-primary"></i> {{ lang._("Labels") }}</div>' +
            '<div class="panel-body" style="padding: 10px 15px;">' +
            (labelRows ? '<div class="table-responsive" style="max-height: 140px; overflow-y: auto;"><table class="table table-striped table-condensed" style="margin-bottom: 0;"><thead><tr><th>{{ lang._("Key") }}</th><th>{{ lang._("Value") }}</th></tr></thead><tbody>' + labelRows + '</tbody></table></div>' : '<div class="text-muted"><em>{{ lang._("No labels configured") }}</em></div>') +
            '</div>' +
            '</div>';

        var rawHtml = '<div class="panel panel-default" id="inspect-raw-section" style="margin-bottom: 0;">' +
            '<div class="panel-heading" style="display: flex; justify-content: space-between; align-items: center; padding: 8px 15px;">' +
            '<a data-toggle="collapse" href="#inspect-raw-collapse" style="font-weight: bold; font-size: 12px; text-transform: uppercase; color: inherit; text-decoration: none;">' +
            '<i class="fa fa-code text-primary"></i> {{ lang._("Raw Configuration / Specification") }} <i class="fa fa-chevron-down text-muted" style="font-size: 10px; margin-left: 5px;"></i>' +
            '</a>' +
            '<div style="display: flex; align-items: center; gap: 8px;">' +
            '<div class="btn-group btn-group-xs" role="group">' +
            '<button type="button" class="btn ' + (currentInspectView === 'json' ? 'btn-primary active' : 'btn-default') + '" id="btn_inspect_raw_json">JSON</button>' +
            '<button type="button" class="btn ' + (currentInspectView === 'yaml' ? 'btn-primary active' : 'btn-default') + '" id="btn_inspect_raw_yaml">YAML</button>' +
            '</div>' +
            '<button type="button" class="btn btn-xs btn-default" id="btn_copy_inspect_raw" title="{{ lang._("Copy Raw Specification") }}"><i class="fa fa-clipboard"></i> {{ lang._("Copy") }}</button>' +
            '</div>' +
            '</div>' +
            '<div id="inspect-raw-collapse" class="panel-collapse collapse">' +
            '<div class="panel-body" style="padding: 0; background: #181818;">' +
            '<pre id="modal-inspect-raw" style="background: #181818; color: #f0f0f0; border: none; font-family: Menlo, Monaco, Consolas, monospace; font-size: 12px; max-height: 380px; overflow-y: auto; padding: 12px; margin-bottom: 0; white-space: pre; border-radius: 0 0 4px 4px;"></pre>' +
            '</div>' +
            '</div>' +
            '</div>';

        var fullContent = headerHtml +
            '<div class="row" style="margin-bottom: 15px;">' +
            '<div class="col-xs-12 col-md-6">' + networkHtml + '</div>' +
            '<div class="col-xs-12 col-md-6">' + storageHtml + '</div>' +
            '</div>' +
            '<div class="row" style="margin-bottom: 15px;">' +
            '<div class="col-xs-12 col-md-6">' + securityHtml + '</div>' +
            '<div class="col-xs-12 col-md-6">' + executionHtml + '</div>' +
            '</div>' +
            labelsHtml +
            rawHtml;

        $('#modal-inspect-content').html(fullContent);
        updateInspectRawView();
    }

    function showContainerInspect(cid, name) {
        $('#modal-inspect-title').html('<i class="fa fa-info-circle text-info"></i> {{ lang._("Container Inspection") }}: ' + $('<div>').text(name || cid).html());
        $('#modal-inspect-content').html('<div class="text-center" style="padding: 40px;"><i class="fa fa-spinner fa-pulse fa-2x"></i><p style="margin-top: 10px;">{{ lang._("Loading inspection data...") }}</p></div>');
        $('#modal-inspect').modal('show');
        ajaxGet('/api/podman/containers/inspect/' + cid, {}, function (data, status) {
            renderInspectModal(data);
        });
    }

    function initTerminal() {
        if (currentTerm) {
            return;
        }

        var TermClass = window.Terminal;
        if (!TermClass) {
            return;
        }

        currentTerm = new TermClass({
            cursorBlink: true,
            theme: {
                background: '#181818',
                foreground: '#f0f0f0',
                cursor: '#5af78e',
                selectionBackground: '#334455'
            },
            fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
            fontSize: 13,
            lineHeight: 1.2
        });

        var FitClass = (window.FitAddon && window.FitAddon.FitAddon) ? window.FitAddon.FitAddon : window.FitAddon;
        if (FitClass) {
            currentFitAddon = new FitClass();
            currentTerm.loadAddon(currentFitAddon);
        }

        var container = document.getElementById('xterm-terminal-container');
        if (container) {
            currentTerm.open(container);
            if (currentFitAddon) {
                currentFitAddon.fit();
            }
        }

        currentTerm.onData(function (data) {
            if (currentWs && currentWs.readyState === WebSocket.OPEN) {
                currentWs.send(data);
            }
        });
    }

    function connectTerminalWs(cid, shell) {
        if (currentWs) {
            try {
                currentWs.close();
            } catch (e) {}
            currentWs = null;
        }

        initTerminal();
        if (!currentTerm) {
            return;
        }

        currentTerm.reset();
        currentTerm.write('\x1b[33m{{ lang._("Connecting to container") }} ' + cid + ' (' + shell + ')...\x1b[0m\r\n');

        var protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        var wsUrl = protocol + '//' + window.location.host + '/api/podman/terminal/ws?cid=' + encodeURIComponent(cid) + '&shell=' + encodeURIComponent(shell);

        try {
            currentWs = new WebSocket(wsUrl);
            currentWs.binaryType = 'arraybuffer';
        } catch (err) {
            currentTerm.write('\r\n\x1b[31m[{{ lang._("WebSocket connection error") }}: ' + err.message + ']\x1b[0m\r\n');
            return;
        }

        currentWs.onopen = function () {
            currentTerm.write('\x1b[32m[{{ lang._("Connected") }}]\x1b[0m\r\n\r\n');
            if (currentFitAddon) {
                currentFitAddon.fit();
                currentWs.send('\x00' + JSON.stringify({
                    type: 'resize',
                    cols: currentTerm.cols,
                    rows: currentTerm.rows
                }));
            }
            currentTerm.focus();
        };

        currentWs.onmessage = function (event) {
            if (event.data instanceof ArrayBuffer) {
                currentTerm.write(new Uint8Array(event.data));
            } else if (typeof event.data === 'string') {
                currentTerm.write(event.data);
            } else if (event.data instanceof Blob) {
                var reader = new FileReader();
                reader.onload = function () {
                    currentTerm.write(new Uint8Array(reader.result));
                };
                reader.readAsArrayBuffer(event.data);
            }
        };

        currentWs.onclose = function () {
            currentTerm.write('\r\n\x1b[31m[{{ lang._("Session disconnected") }}]\x1b[0m\r\n');
        };

        currentWs.onerror = function () {
            currentTerm.write('\r\n\x1b[31m[{{ lang._("WebSocket error") }}]\x1b[0m\r\n');
        };
    }

    function showContainerCli(cid, name) {
        currentCliContainerId = cid;
        currentCliContainerName = name;
        $('#modal-cli-title').html('<i class="fa fa-terminal text-warning"></i> {{ lang._("Container Terminal") }}: ' + $('<div>').text(name || cid).html());
        $('#modal-cli').modal('show');
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
        window.scrollTo(0, 0);
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

        $(document).on('click', '.btn-copy-val', function () {
            var val = $(this).data('copy-val');
            copyToClipboard(val, this);
        });

        $(document).on('click', '#btn_copy_inspect_raw', function () {
            var text = $('#modal-inspect-raw').text();
            copyToClipboard(text, this);
        });

        $(document).on('click', '#btn_inspect_raw_json', function () {
            currentInspectView = 'json';
            $('#btn_inspect_raw_json').addClass('active btn-primary').removeClass('btn-default');
            $('#btn_inspect_raw_yaml').removeClass('active btn-primary').addClass('btn-default');
            updateInspectRawView();
        });

        $(document).on('click', '#btn_inspect_raw_yaml', function () {
            currentInspectView = 'yaml';
            $('#btn_inspect_raw_yaml').addClass('active btn-primary').removeClass('btn-default');
            $('#btn_inspect_raw_json').removeClass('active btn-primary').addClass('btn-default');
            updateInspectRawView();
        });

        $(document).on('input', '#inspect-env-filter', function () {
            var q = ($(this).val() || '').toLowerCase();
            $('#inspect-env-list .inspect-env-item').each(function () {
                var itemText = $(this).text().toLowerCase();
                $(this).toggle(itemText.indexOf(q) !== -1);
            });
        });

        $('#btn_refresh_modal_logs').click(function () {
            fetchLogsContent();
        });

        $('#modal-cli').on('shown.bs.modal', function () {
            var shell = $('#cli-shell').val() || '/bin/sh';
            if (currentCliContainerId) {
                connectTerminalWs(currentCliContainerId, shell);
            }
            $(window).on('resize.terminal', function () {
                if (currentFitAddon && currentTerm) {
                    currentFitAddon.fit();
                    if (currentWs && currentWs.readyState === WebSocket.OPEN) {
                        currentWs.send('\x00' + JSON.stringify({
                            type: 'resize',
                            cols: currentTerm.cols,
                            rows: currentTerm.rows
                        }));
                    }
                }
            });
        });

        $('#modal-cli').on('hidden.bs.modal', function () {
            $(window).off('resize.terminal');
            if (currentWs) {
                try {
                    currentWs.close();
                } catch (e) {}
                currentWs = null;
            }
        });

        $('#cli-shell').change(function () {
            var shell = $(this).val() || '/bin/sh';
            if (currentCliContainerId) {
                connectTerminalWs(currentCliContainerId, shell);
            }
        });

        $('#btn_clear_cli').click(function () {
            if (currentTerm) {
                currentTerm.clear();
                currentTerm.focus();
            }
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
                        <th style="width: 180px;">{{ lang._('Created') }}</th>
                        <th style="width: 230px;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="6" class="text-center" id="containers-loading"><i class="fa fa-spinner fa-pulse"></i> {{ lang._('Loading containers...') }}</td></tr>
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
    <div class="modal-dialog modal-lg" style="width: 85%; max-width: 1200px;" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                <h4 class="modal-title" id="modal-inspect-title"><i class="fa fa-info-circle text-info"></i> {{ lang._('Container Inspection') }}</h4>
            </div>
            <div class="modal-body" style="padding: 15px; max-height: calc(100vh - 180px); overflow-y: auto;">
                <div id="modal-inspect-content"></div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-primary" data-dismiss="modal">{{ lang._('Close') }}</button>
            </div>
        </div>
    </div>
</div>

<!-- Container Terminal Modal -->
<div class="modal fade" id="modal-cli" tabindex="-1" role="dialog" aria-labelledby="modal-cli-title" aria-hidden="true">
    <div class="modal-dialog modal-lg" style="width: 85%; max-width: 1100px;" role="document">
        <div class="modal-content" style="background: #181818; color: #f0f0f0; border: 1px solid #2a2a2a; border-radius: 6px;">
            <div class="modal-header" style="display: flex; justify-content: space-between; align-items: center; background: #181818; border-bottom: 1px solid #2a2a2a; padding: 10px 15px;">
                <h4 class="modal-title" id="modal-cli-title" style="margin: 0; font-size: 15px; font-weight: bold; color: #f0f0f0;">
                    <i class="fa fa-terminal text-warning"></i> {{ lang._('Container Terminal') }}
                </h4>
                <div style="display: flex; align-items: center; gap: 8px;">
                    <div style="display: inline-flex; align-items: center; gap: 5px;">
                        <label for="cli-shell" style="margin: 0; font-size: 12px; font-weight: normal; color: #aaa;">{{ lang._('Shell') }}:</label>
                        <input type="text" class="form-control input-sm" id="cli-shell" list="cli-shell-list" value="/bin/sh" style="width: 100px; height: 26px; padding: 2px 8px; background: #242424; color: #f0f0f0; border: 1px solid #333;" />
                        <datalist id="cli-shell-list">
                            <option value="/bin/sh">
                            <option value="/bin/bash">
                            <option value="/bin/csh">
                            <option value="/bin/zsh">
                            <option value="/bin/ash">
                        </datalist>
                    </div>
                    <button type="button" class="btn btn-xs btn-default" id="btn_clear_cli" title="{{ lang._('Clear Terminal') }}" style="background: #242424; color: #f0f0f0; border: 1px solid #333;"><i class="fa fa-eraser"></i> {{ lang._('Clear') }}</button>
                    <button type="button" class="close" data-dismiss="modal" aria-label="Close" style="color: #fff; opacity: 0.8; margin-left: 10px;"><span aria-hidden="true">&times;</span></button>
                </div>
            </div>
            <div class="modal-body" style="padding: 10px; background: #181818; border-radius: 0 0 6px 6px;">
                <div id="xterm-terminal-container" style="height: 480px; width: 100%; background: #181818; border: 1px solid #2a2a2a; border-radius: 4px; padding: 4px;"></div>
            </div>
        </div>
    </div>
</div>
