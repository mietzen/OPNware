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

<link rel="stylesheet" href="{{ cache_safe('/ui/css/vendor/xterm/xterm.css') }}">
<script src="{{ cache_safe('/ui/js/vendor/xterm/xterm.js') }}"></script>
<script src="{{ cache_safe('/ui/js/vendor/xterm/addon-fit.js') }}"></script>

<style>
.modal-title > i,
.modal-title > span.fa,
.modal-title > .fa {
    margin-right: 10px;
}
.docker-stat-card {
    display: flex;
    align-items: center;
    padding: 15px;
}
.docker-stat-icon {
    font-size: 2.2em;
    margin-right: 15px;
    opacity: 0.8;
}
.docker-stat-content {
    flex-grow: 1;
}
.docker-stat-value {
    font-size: 1.5em;
    font-weight: bold;
    margin-top: 2px;
}
.term-container {
    background: #000;
    padding: 5px;
    border-radius: 4px;
    height: 450px;
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

    function decodeHtml(str) {
        if (!str || typeof str !== 'string' || str.indexOf('&') === -1) return str;
        return str.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#039;/g, "'");
    }

    function ansiToHtml(str) {
        if (!str) return '';
        var html = decodeHtml(String(str))
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");

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
        return html;
    }

    function formatBytes(bytes, decimals) {
        if (!bytes || bytes === 0) return '0 B';
        var k = 1024;
        var dm = decimals < 0 ? 0 : decimals;
        var sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        var i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
    }

    function updateStats() {
        ajaxGet('/api/docker/system/stats', {}, function(data, status) {
            if (status === 'success' && data && data.status === 'ok') {
                var items = data.items || [];
                var running = items.length;
                $('#stat_containers_running').text(running);
            }
        });
        ajaxGet('/api/docker/containers/list', {}, function(data, status) {
            if (status === 'success' && data && data.status === 'ok') {
                var items = data.items || [];
                var total = items.length;
                var running = items.filter(function(c) {
                    var st = (c.State || c.Status || '').toLowerCase();
                    return st.indexOf('up') !== -1 || st.indexOf('running') !== -1;
                }).length;
                $('#stat_containers').text(running + ' / ' + total);
            }
        });
        ajaxGet('/api/docker/images/list', {}, function(data, status) {
            if (status === 'success' && data && data.status === 'ok') {
                var items = data.items || [];
                $('#stat_images').text(items.length);
            }
        });
        ajaxGet('/api/docker/volumes/list', {}, function(data, status) {
            if (status === 'success' && data && data.status === 'ok') {
                var items = data.items || [];
                $('#stat_volumes').text(items.length);
            }
        });
    }

    function refreshContainers() {
        ajaxGet('/api/docker/containers/list', {}, function(data, status) {
            var tbody = $('#table_containers tbody');
            tbody.empty();
            if (status !== 'success' || !data || data.status !== 'ok' || !data.items || data.items.length === 0) {
                tbody.append('<tr><td colspan="7" class="text-center text-muted"><em>{{ lang._("No containers found.") }}</em></td></tr>');
                return;
            }
            data.items.forEach(function(c) {
                var cid = c.ID || c.Id || '';
                var shortId = cid.substring(0, 12);
                var name = c.Names || c.Name || '';
                if (Array.isArray(name)) name = name[0];
                name = String(name).replace(/^\//, '');
                var image = c.Image || '';
                var state = (c.State || c.Status || '').toLowerCase();
                var isRunning = state.indexOf('up') !== -1 || state.indexOf('running') !== -1;
                var statusBadge = isRunning
                    ? '<span class="label label-success"><i class="fa fa-play"></i> Running</span>'
                    : '<span class="label label-default"><i class="fa fa-stop"></i> Stopped</span>';
                var ports = c.Ports || '';
                var created = c.CreatedAt || c.Created || '';

                var tr = $('<tr></tr>');
                tr.append('<td><strong>' + name + '</strong><br><small class="text-muted">' + shortId + '</small></td>');
                tr.append('<td><code>' + image + '</code></td>');
                tr.append('<td>' + statusBadge + '</td>');
                tr.append('<td><small>' + (ports || '-') + '</small></td>');
                tr.append('<td><small>' + created + '</small></td>');

                var actions = $('<td class="text-right"></td>');
                if (isRunning) {
                    actions.append('<button class="btn btn-xs btn-default act-stop" data-id="' + cid + '" title="Stop"><i class="fa fa-stop"></i></button> ');
                    actions.append('<button class="btn btn-xs btn-default act-restart" data-id="' + cid + '" title="Restart"><i class="fa fa-refresh"></i></button> ');
                    actions.append('<button class="btn btn-xs btn-default act-cli" data-id="' + cid + '" data-name="' + name + '" title="Shell"><i class="fa fa-terminal"></i></button> ');
                } else {
                    actions.append('<button class="btn btn-xs btn-success act-start" data-id="' + cid + '" title="Start"><i class="fa fa-play"></i></button> ');
                }
                actions.append('<button class="btn btn-xs btn-info act-logs" data-id="' + cid + '" data-name="' + name + '" title="Logs"><i class="fa fa-file-text-o"></i></button> ');
                actions.append('<button class="btn btn-xs btn-default act-inspect" data-id="' + cid + '" title="Inspect"><i class="fa fa-search"></i></button> ');
                actions.append('<button class="btn btn-xs btn-danger act-delete" data-id="' + cid + '" title="Remove"><i class="fa fa-trash-o"></i></button>');

                tr.append(actions);
                tbody.append(tr);
            });
        });
    }

    function refreshImages() {
        ajaxGet('/api/docker/images/list', {}, function(data, status) {
            var tbody = $('#table_images tbody');
            tbody.empty();
            if (status !== 'success' || !data || data.status !== 'ok' || !data.items || data.items.length === 0) {
                tbody.append('<tr><td colspan="6" class="text-center text-muted"><em>{{ lang._("No images found.") }}</em></td></tr>');
                return;
            }
            data.items.forEach(function(img) {
                var id = img.ID || img.Id || '';
                var shortId = id.replace(/^sha256:/, '').substring(0, 12);
                var repo = img.Repository || '<none>';
                var tag = img.Tag || '<none>';
                var size = img.Size || '';
                var created = img.CreatedAt || img.CreatedSince || '';

                var tr = $('<tr></tr>');
                tr.append('<td><strong>' + repo + '</strong></td>');
                tr.append('<td><span class="label label-info">' + tag + '</span></td>');
                tr.append('<td><code>' + shortId + '</code></td>');
                tr.append('<td>' + size + '</td>');
                tr.append('<td><small>' + created + '</small></td>');

                var actions = $('<td class="text-right"></td>');
                actions.append('<button class="btn btn-xs btn-danger act-img-delete" data-id="' + (repo !== '<none>' ? repo + ':' + tag : id) + '" title="Remove"><i class="fa fa-trash-o"></i></button>');
                tr.append(actions);
                tbody.append(tr);
            });
        });
    }

    function refreshVolumes() {
        ajaxGet('/api/docker/volumes/list', {}, function(data, status) {
            var tbody = $('#table_volumes tbody');
            tbody.empty();
            if (status !== 'success' || !data || data.status !== 'ok' || !data.items || data.items.length === 0) {
                tbody.append('<tr><td colspan="5" class="text-center text-muted"><em>{{ lang._("No volumes found.") }}</em></td></tr>');
                return;
            }
            data.items.forEach(function(vol) {
                var name = vol.Name || '';
                var driver = vol.Driver || 'local';
                var scope = vol.Scope || 'local';
                var mount = vol.Mountpoint || '';

                var tr = $('<tr></tr>');
                tr.append('<td><strong>' + name + '</strong></td>');
                tr.append('<td><span class="label label-default">' + driver + '</span></td>');
                tr.append('<td>' + scope + '</td>');
                tr.append('<td><small class="text-muted">' + mount + '</small></td>');

                var actions = $('<td class="text-right"></td>');
                actions.append('<button class="btn btn-xs btn-default act-vol-inspect" data-name="' + name + '" title="Inspect"><i class="fa fa-search"></i></button> ');
                actions.append('<button class="btn btn-xs btn-danger act-vol-delete" data-name="' + name + '" title="Remove"><i class="fa fa-trash-o"></i></button>');
                tr.append(actions);
                tbody.append(tr);
            });
        });
    }

    $(document).ready(function() {
        updateStats();
        refreshContainers();
        refreshImages();
        refreshVolumes();

        // Containers Actions
        $(document).on('click', '.act-start', function() {
            var id = $(this).data('id');
            ajaxCall('/api/docker/containers/start/' + id, {}, function() {
                refreshContainers();
                updateStats();
            });
        });

        $(document).on('click', '.act-stop', function() {
            var id = $(this).data('id');
            ajaxCall('/api/docker/containers/stop/' + id, {}, function() {
                refreshContainers();
                updateStats();
            });
        });

        $(document).on('click', '.act-restart', function() {
            var id = $(this).data('id');
            ajaxCall('/api/docker/containers/restart/' + id, {}, function() {
                refreshContainers();
                updateStats();
            });
        });

        $(document).on('click', '.act-delete', function() {
            var id = $(this).data('id');
            if (confirm("{{ lang._('Are you sure you want to remove this container?') }}")) {
                ajaxCall('/api/docker/containers/delete/' + id, {}, function() {
                    refreshContainers();
                    updateStats();
                });
            }
        });

        $(document).on('click', '.act-logs', function() {
            currentLogContainerId = $(this).data('id');
            var name = $(this).data('name');
            $('#modal_logs_title').text("Logs: " + name);
            $('#modal_logs_content').html('<div class="text-center"><i class="fa fa-spinner fa-spin"></i> Loading...</div>');
            $('#modal_logs').modal('show');
            loadLogs();
        });

        function loadLogs() {
            if (!currentLogContainerId) return;
            ajaxGet('/api/docker/containers/logs/' + currentLogContainerId, {}, function(data, status) {
                if (status === 'success' && data) {
                    var out = data.output || data.message || '';
                    $('#modal_logs_content').html('<pre style="background:#1e1e1e;color:#f1f1f0;max-height:500px;overflow:auto;">' + ansiToHtml(out) + '</pre>');
                }
            });
        }

        $('#btn_logs_refresh').click(function() {
            loadLogs();
        });

        $(document).on('click', '.act-inspect', function() {
            var id = $(this).data('id');
            ajaxGet('/api/docker/containers/inspect/' + id, {}, function(data, status) {
                if (status === 'success' && data) {
                    $('#modal_inspect_content').text(JSON.stringify(data.items || data, null, 2));
                    $('#modal_inspect').modal('show');
                }
            });
        });

        // Web Terminal Modal
        $(document).on('click', '.act-cli', function() {
            currentCliContainerId = $(this).data('id');
            currentCliContainerName = $(this).data('name');
            $('#modal_cli_title').text("Shell: " + currentCliContainerName);
            $('#modal_cli').modal('show');
        });

        $('#modal_cli').on('shown.bs.modal', function() {
            if (!currentCliContainerId) return;
            if (currentTerm) {
                currentTerm.dispose();
            }
            $('#terminal_container').empty();

            currentTerm = new Terminal({
                cursorBlink: true,
                theme: {
                    background: '#000000',
                    foreground: '#f1f1f0',
                    cursor: '#ffffff'
                }
            });
            currentFitAddon = new FitAddon.FitAddon();
            currentTerm.loadAddon(currentFitAddon);
            currentTerm.open(document.getElementById('terminal_container'));
            currentFitAddon.fit();

            var loc = window.location;
            var wsProtocol = (loc.protocol === 'https:') ? 'wss:' : 'ws:';
            var wsUrl = wsProtocol + '//' + loc.host + '/api/docker/terminal/ws?id=' + encodeURIComponent(currentCliContainerId);

            currentWs = new WebSocket(wsUrl);
            currentWs.binaryType = 'arraybuffer';

            currentWs.onopen = function() {
                currentTerm.write('\r\n\x1b[32m[Connected to container shell]\x1b[0m\r\n');
            };

            currentWs.onmessage = function(ev) {
                if (typeof ev.data === 'string') {
                    currentTerm.write(ev.data);
                } else {
                    var arr = new Uint8Array(ev.data);
                    currentTerm.write(arr);
                }
            };

            currentWs.onerror = function() {
                currentTerm.write('\r\n\x1b[31m[WebSocket Connection Error]\x1b[0m\r\n');
            };

            currentWs.onclose = function() {
                currentTerm.write('\r\n\x1b[33m[Connection Closed]\x1b[0m\r\n');
            };

            currentTerm.onData(function(data) {
                if (currentWs && currentWs.readyState === WebSocket.OPEN) {
                    currentWs.send(data);
                }
            });
        });

        $('#modal_cli').on('hidden.bs.modal', function() {
            if (currentWs) {
                currentWs.close();
                currentWs = null;
            }
            if (currentTerm) {
                currentTerm.dispose();
                currentTerm = null;
            }
        });

        // Image Actions
        $('#btn_img_pull').click(function() {
            $('#modal_img_pull').modal('show');
        });

        $('#btn_do_pull').click(function() {
            var img = $('#pull_image_name').val().trim();
            if (!img) return;
            $('#btn_do_pull').prop('disabled', true).html('<i class="fa fa-spinner fa-spin"></i> Pulling...');
            ajaxCall('/api/docker/images/pull', {image: img}, function(data) {
                $('#btn_do_pull').prop('disabled', false).text('Pull Image');
                $('#modal_img_pull').modal('hide');
                refreshImages();
                updateStats();
            });
        });

        $(document).on('click', '.act-img-delete', function() {
            var id = $(this).data('id');
            if (confirm("{{ lang._('Are you sure you want to remove this image?') }}")) {
                ajaxCall('/api/docker/images/delete', {id: id}, function() {
                    refreshImages();
                    updateStats();
                });
            }
        });

        $('#btn_img_prune').click(function() {
            if (confirm("{{ lang._('Prune all unused Docker images?') }}")) {
                ajaxCall('/api/docker/images/prune', {}, function() {
                    refreshImages();
                    updateStats();
                });
            }
        });

        // Volume Actions
        $('#btn_vol_create').click(function() {
            $('#modal_vol_create').modal('show');
        });

        $('#btn_do_vol_create').click(function() {
            var name = $('#create_volume_name').val().trim();
            if (!name) return;
            ajaxCall('/api/docker/volumes/create', {name: name}, function() {
                $('#modal_vol_create').modal('hide');
                refreshVolumes();
                updateStats();
            });
        });

        $(document).on('click', '.act-vol-delete', function() {
            var name = $(this).data('name');
            if (confirm("{{ lang._('Are you sure you want to remove volume: ') }}" + name + "?")) {
                ajaxCall('/api/docker/volumes/delete', {name: name}, function() {
                    refreshVolumes();
                    updateStats();
                });
            }
        });

        $('#btn_vol_prune').click(function() {
            if (confirm("{{ lang._('Prune all unused Docker volumes?') }}")) {
                ajaxCall('/api/docker/volumes/prune', {}, function() {
                    refreshVolumes();
                    updateStats();
                });
            }
        });

        $('#btn_system_prune').click(function() {
            if (confirm("{{ lang._('Prune all stopped containers, unused networks, and dangling images?') }}")) {
                ajaxCall('/api/docker/system/prune', {}, function() {
                    refreshContainers();
                    refreshImages();
                    refreshVolumes();
                    updateStats();
                });
            }
        });

        // Auto Refresh
        $('#btn_refresh_all').click(function() {
            updateStats();
            refreshContainers();
            refreshImages();
            refreshVolumes();
        });
    });
</script>

<div class="row" style="margin-bottom: 20px;">
    <div class="col-md-3">
        <div class="panel panel-default">
            <div class="docker-stat-card">
                <div class="docker-stat-icon text-primary"><i class="fa fa-cubes"></i></div>
                <div class="docker-stat-content">
                    <div class="text-muted">{{ lang._('Containers') }}</div>
                    <div class="docker-stat-value" id="stat_containers">-</div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="panel panel-default">
            <div class="docker-stat-card">
                <div class="docker-stat-icon text-info"><i class="fa fa-clone"></i></div>
                <div class="docker-stat-content">
                    <div class="text-muted">{{ lang._('Images') }}</div>
                    <div class="docker-stat-value" id="stat_images">-</div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="panel panel-default">
            <div class="docker-stat-card">
                <div class="docker-stat-icon text-warning"><i class="fa fa-database"></i></div>
                <div class="docker-stat-content">
                    <div class="text-muted">{{ lang._('Volumes') }}</div>
                    <div class="docker-stat-value" id="stat_volumes">-</div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="panel panel-default">
            <div class="docker-stat-card" style="justify-content: space-between;">
                <div style="display:flex; align-items:center;">
                    <div class="docker-stat-icon text-success"><i class="fa fa-recycle"></i></div>
                    <div class="docker-stat-content">
                        <div class="text-muted">{{ lang._('Maintenance') }}</div>
                        <div class="docker-stat-value"><button class="btn btn-xs btn-default" id="btn_system_prune"><i class="fa fa-trash-o"></i> {{ lang._('Prune System') }}</button></div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<ul class="nav nav-tabs" role="tablist" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#tab_containers"><b><i class="fa fa-cubes"></i> {{ lang._('Containers') }}</b></a></li>
    <li><a data-toggle="tab" href="#tab_images"><b><i class="fa fa-clone"></i> {{ lang._('Images') }}</b></a></li>
    <li><a data-toggle="tab" href="#tab_volumes"><b><i class="fa fa-database"></i> {{ lang._('Volumes') }}</b></a></li>
</ul>

<div class="content-box tab-content">
    <!-- Containers Tab -->
    <div id="tab_containers" class="tab-pane fade in active">
        <div class="pull-right" style="margin-bottom: 10px;">
            <button class="btn btn-sm btn-default" id="btn_refresh_all"><i class="fa fa-refresh"></i> {{ lang._('Refresh') }}</button>
        </div>
        <table class="table table-striped table-hover" id="table_containers">
            <thead>
                <tr>
                    <th>{{ lang._('Name / ID') }}</th>
                    <th>{{ lang._('Image') }}</th>
                    <th>{{ lang._('Status') }}</th>
                    <th>{{ lang._('Port Mappings') }}</th>
                    <th>{{ lang._('Created') }}</th>
                    <th class="text-right">{{ lang._('Actions') }}</th>
                </tr>
            </thead>
            <tbody>
                <tr><td colspan="6" class="text-center"><i class="fa fa-spinner fa-spin"></i> Loading...</td></tr>
            </tbody>
        </table>
    </div>

    <!-- Images Tab -->
    <div id="tab_images" class="tab-pane fade">
        <div class="pull-right" style="margin-bottom: 10px;">
            <button class="btn btn-sm btn-primary" id="btn_img_pull"><i class="fa fa-download"></i> {{ lang._('Pull Image') }}</button>
            <button class="btn btn-sm btn-default" id="btn_img_prune"><i class="fa fa-trash-o"></i> {{ lang._('Prune Unused') }}</button>
        </div>
        <table class="table table-striped table-hover" id="table_images">
            <thead>
                <tr>
                    <th>{{ lang._('Repository') }}</th>
                    <th>{{ lang._('Tag') }}</th>
                    <th>{{ lang._('ID') }}</th>
                    <th>{{ lang._('Size') }}</th>
                    <th>{{ lang._('Created') }}</th>
                    <th class="text-right">{{ lang._('Actions') }}</th>
                </tr>
            </thead>
            <tbody>
                <tr><td colspan="6" class="text-center"><i class="fa fa-spinner fa-spin"></i> Loading...</td></tr>
            </tbody>
        </table>
    </div>

    <!-- Volumes Tab -->
    <div id="tab_volumes" class="tab-pane fade">
        <div class="pull-right" style="margin-bottom: 10px;">
            <button class="btn btn-sm btn-primary" id="btn_vol_create"><i class="fa fa-plus"></i> {{ lang._('Create Volume') }}</button>
            <button class="btn btn-sm btn-default" id="btn_vol_prune"><i class="fa fa-trash-o"></i> {{ lang._('Prune Unused') }}</button>
        </div>
        <table class="table table-striped table-hover" id="table_volumes">
            <thead>
                <tr>
                    <th>{{ lang._('Name') }}</th>
                    <th>{{ lang._('Driver') }}</th>
                    <th>{{ lang._('Scope') }}</th>
                    <th>{{ lang._('Mountpoint') }}</th>
                    <th class="text-right">{{ lang._('Actions') }}</th>
                </tr>
            </thead>
            <tbody>
                <tr><td colspan="5" class="text-center"><i class="fa fa-spinner fa-spin"></i> Loading...</td></tr>
            </tbody>
        </table>
    </div>
</div>

<!-- Logs Modal -->
<div class="modal fade" id="modal_logs" tabindex="-1" role="dialog">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title" id="modal_logs_title"><i class="fa fa-file-text-o"></i> Container Logs</h4>
            </div>
            <div class="modal-body" id="modal_logs_content">
                <div class="text-center"><i class="fa fa-spinner fa-spin"></i> Loading...</div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" id="btn_logs_refresh"><i class="fa fa-refresh"></i> Refresh</button>
                <button type="button" class="btn btn-primary" data-dismiss="modal">Close</button>
            </div>
        </div>
    </div>
</div>

<!-- Inspect Modal -->
<div class="modal fade" id="modal_inspect" tabindex="-1" role="dialog">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title"><i class="fa fa-search"></i> Inspect Details</h4>
            </div>
            <div class="modal-body">
                <pre id="modal_inspect_content" style="max-height: 500px; overflow: auto; background: #1e1e1e; color: #f1f1f0;"></pre>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-primary" data-dismiss="modal">Close</button>
            </div>
        </div>
    </div>
</div>

<!-- Web Terminal Modal -->
<div class="modal fade" id="modal_cli" tabindex="-1" role="dialog">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title" id="modal_cli_title"><i class="fa fa-terminal"></i> Container Shell</h4>
            </div>
            <div class="modal-body">
                <div id="terminal_container" class="term-container"></div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-primary" data-dismiss="modal">Close</button>
            </div>
        </div>
    </div>
</div>

<!-- Pull Image Modal -->
<div class="modal fade" id="modal_img_pull" tabindex="-1" role="dialog">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title"><i class="fa fa-download"></i> Pull Image</h4>
            </div>
            <div class="modal-body">
                <div class="form-group">
                    <label for="pull_image_name">{{ lang._('Image Name (e.g. nginx:alpine, pihole/pihole:latest)') }}</label>
                    <input type="text" class="form-control" id="pull_image_name" placeholder="nginx:alpine">
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
                <button type="button" class="btn btn-primary" id="btn_do_pull">Pull Image</button>
            </div>
        </div>
    </div>
</div>

<!-- Create Volume Modal -->
<div class="modal fade" id="modal_vol_create" tabindex="-1" role="dialog">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title"><i class="fa fa-plus"></i> Create Volume</h4>
            </div>
            <div class="modal-body">
                <div class="form-group">
                    <label for="create_volume_name">{{ lang._('Volume Name') }}</label>
                    <input type="text" class="form-control" id="create_volume_name" placeholder="my_data_volume">
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
                <button type="button" class="btn btn-primary" id="btn_do_vol_create">Create</button>
            </div>
        </div>
    </div>
</div>
