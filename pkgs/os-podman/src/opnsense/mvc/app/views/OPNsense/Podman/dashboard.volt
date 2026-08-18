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

    function loadContainers() {
        ajaxGet('/api/podman/containers/list', {}, function (data, status) {
            var $tbody = $('#grid-containers tbody');
            var items = (data && data.items) ? data.items : [];
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

                var actions = '';
                if (!isRunning) {
                    actions += '<button class="btn btn-xs btn-default act-start" data-id="' + cid + '" title="{{ lang._("Start") }}"><i class="fa fa-play text-success"></i></button> ';
                } else {
                    actions += '<button class="btn btn-xs btn-default act-stop" data-id="' + cid + '" title="{{ lang._("Stop") }}"><i class="fa fa-stop text-warning"></i></button> ';
                    actions += '<button class="btn btn-xs btn-default act-restart" data-id="' + cid + '" title="{{ lang._("Restart") }}"><i class="fa fa-refresh text-info"></i></button> ';
                    actions += '<button class="btn btn-xs btn-default act-kill" data-id="' + cid + '" title="{{ lang._("Force Stop") }}"><i class="fa fa-bolt text-danger"></i></button> ';
                }
                actions += '<button class="btn btn-xs btn-default act-logs" data-id="' + cid + '" data-name="' + $('<div>').text(names).html() + '" title="{{ lang._("View Logs") }}"><i class="fa fa-file-text-o text-primary"></i></button> ';
                actions += '<button class="btn btn-xs btn-default act-inspect" data-id="' + cid + '" data-name="' + $('<div>').text(names).html() + '" title="{{ lang._("Inspect Container") }}"><i class="fa fa-info-circle text-info"></i></button> ';
                actions += '<button class="btn btn-xs btn-default act-delete-container" data-id="' + cid + '" data-name="' + $('<div>').text(names).html() + '" title="{{ lang._("Delete Container") }}"><i class="fa fa-trash text-danger"></i></button>';

                rows += '<tr>' +
                    '<td><code>' + cid + '</code></td>' +
                    '<td><strong>' + $('<div>').text(names).html() + '</strong></td>' +
                    '<td>' + $('<div>').text(image).html() + '</td>' +
                    '<td><span class="label ' + badgeClass + '">' + $('<div>').text(state).html() + '</span></td>' +
                    '<td>' + $('<div>').text(created).html() + '</td>' +
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
            var rows = '';
            $.each(items, function (idx, img) {
                var repo = Array.isArray(img.Names) ? img.Names.join(', ') : (img.Repository || img.History || 'none');
                var iid = (img.Id || img.ID || '').substring(0, 12);
                var size = img.Size ? (typeof img.Size === 'number' ? (img.Size / (1024*1024)).toFixed(1) + ' MB' : img.Size) : '';
                var created = img.Created || img.CreatedAt || '';

                var actions = '<button class="btn btn-xs btn-default act-delete-image" data-id="' + iid + '" data-name="' + $('<div>').text(repo).html() + '" title="{{ lang._("Delete Image") }}"><i class="fa fa-trash text-danger"></i></button>';

                rows += '<tr>' +
                    '<td><strong>' + $('<div>').text(repo).html() + '</strong></td>' +
                    '<td><code>' + iid + '</code></td>' +
                    '<td>' + size + '</td>' +
                    '<td>' + $('<div>').text(created).html() + '</td>' +
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
            var rows = '';
            $.each(items, function (idx, v) {
                var vname = v.Name || '';
                var actions = '<button class="btn btn-xs btn-default act-delete-volume" data-name="' + $('<div>').text(vname).html() + '" title="{{ lang._("Delete Volume") }}"><i class="fa fa-trash text-danger"></i></button>';

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
                    actions = '<span class="text-muted"><i class="fa fa-lock" title="{{ lang._("Default system network") }}"></i></span>';
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
            $('#modal-logs-body').text(text);
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

        // 5-second dynamic auto-refresh for real-time visibility
        autoRefreshInterval = setInterval(refreshActiveTab, 5000);

        $('#maintabs a[data-toggle="tab"]').on('shown.bs.tab', function () {
            refreshActiveTab();
        });

        // Lifecycle Actions
        $(document).on('click', '.act-start', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/podman/containers/start/' + cid, {}, function () { loadContainers(); loadSystemDf(); });
        });

        $(document).on('click', '.act-stop', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/podman/containers/stop/' + cid, {}, function () { loadContainers(); loadSystemDf(); });
        });

        $(document).on('click', '.act-restart', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/podman/containers/restart/' + cid, {}, function () { loadContainers(); loadSystemDf(); });
        });

        $(document).on('click', '.act-kill', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/podman/containers/kill/' + cid, {}, function () { loadContainers(); loadSystemDf(); });
        });

        // Logs & Inspect
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

        $('#btn_refresh_modal_logs').click(function () {
            fetchLogsContent();
        });

        // Deletion
        $(document).on('click', '.act-delete-container', function () {
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

<div class="content-box tab-content" style="padding-top: 0;">
    <!-- Containers Tab -->
    <div id="tab-containers" class="tab-pane fade in active">
        <div class="table-responsive">
            <table class="table table-striped table-hover" id="grid-containers">
                <thead>
                    <tr>
                        <th style="width: 120px;">{{ lang._('Container ID') }}</th>
                        <th>{{ lang._('Name') }}</th>
                        <th>{{ lang._('Image') }}</th>
                        <th>{{ lang._('Status') }}</th>
                        <th>{{ lang._('Created') }}</th>
                        <th style="width: 200px;">{{ lang._('Actions') }}</th>
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
            <table class="table table-striped table-hover" id="grid-images">
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
            <table class="table table-striped table-hover" id="grid-volumes">
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
            <table class="table table-striped table-hover" id="grid-networks">
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
