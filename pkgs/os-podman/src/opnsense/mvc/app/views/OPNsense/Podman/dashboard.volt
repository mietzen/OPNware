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

    function refreshActiveTab() {
        var activeTab = $('#maintabs li.active a').attr('href');
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
                $tbody.html('<tr><td colspan="4" class="text-center"><em>{{ lang._("No images found") }}</em></td></tr>');
                return;
            }
            var rows = '';
            $.each(items, function (idx, img) {
                var repo = Array.isArray(img.Names) ? img.Names.join(', ') : (img.Repository || img.History || 'none');
                var iid = (img.Id || img.ID || '').substring(0, 12);
                var size = img.Size ? (typeof img.Size === 'number' ? (img.Size / (1024*1024)).toFixed(1) + ' MB' : img.Size) : '';
                var created = img.Created || img.CreatedAt || '';

                rows += '<tr>' +
                    '<td><strong>' + $('<div>').text(repo).html() + '</strong></td>' +
                    '<td><code>' + iid + '</code></td>' +
                    '<td>' + size + '</td>' +
                    '<td>' + $('<div>').text(created).html() + '</td>' +
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
                $tbody.html('<tr><td colspan="3" class="text-center"><em>{{ lang._("No volumes found") }}</em></td></tr>');
                return;
            }
            var rows = '';
            $.each(items, function (idx, v) {
                rows += '<tr>' +
                    '<td><strong>' + $('<div>').text(v.Name || '').html() + '</strong></td>' +
                    '<td>' + $('<div>').text(v.Driver || '').html() + '</td>' +
                    '<td><code>' + $('<div>').text(v.Mountpoint || '').html() + '</code></td>' +
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
                $tbody.html('<tr><td colspan="4" class="text-center"><em>{{ lang._("No networks found") }}</em></td></tr>');
                return;
            }
            var rows = '';
            $.each(items, function (idx, net) {
                var subnets = '';
                if (Array.isArray(net.Subnets)) {
                    subnets = net.Subnets.map(function(s) { return s.Subnet || ''; }).join(', ');
                }
                rows += '<tr>' +
                    '<td><strong>' + $('<div>').text(net.Name || '').html() + '</strong></td>' +
                    '<td><code>' + ((net.ID || net.Id || '').substring(0, 12)) + '</code></td>' +
                    '<td>' + $('<div>').text(net.Driver || 'bridge').html() + '</td>' +
                    '<td>' + $('<div>').text(subnets).html() + '</td>' +
                    '</tr>';
            });
            $tbody.html(rows);
        });
    }

    $(document).ready(function () {
        updateServiceControlUI('podman');
        loadContainers();
        loadImages();
        loadVolumes();
        loadNetworks();

        // 5-second dynamic auto-refresh for real-time visibility
        autoRefreshInterval = setInterval(refreshActiveTab, 5000);

        $('#maintabs a[data-toggle="tab"]').on('shown.bs.tab', function () {
            refreshActiveTab();
        });

        $(document).on('click', '.act-start', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/podman/containers/start/' + cid, {}, function () { loadContainers(); });
        });

        $(document).on('click', '.act-stop', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/podman/containers/stop/' + cid, {}, function () { loadContainers(); });
        });

        $(document).on('click', '.act-restart', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/podman/containers/restart/' + cid, {}, function () { loadContainers(); });
        });

        $(document).on('click', '.act-kill', function () {
            var cid = $(this).data('id');
            ajaxCall('/api/podman/containers/kill/' + cid, {}, function () { loadContainers(); });
        });
    });
</script>

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
                        <th style="width: 140px;">{{ lang._('Actions') }}</th>
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
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="4" class="text-center"><em>{{ lang._('No images found') }}</em></td></tr>
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
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="3" class="text-center"><em>{{ lang._('No volumes found') }}</em></td></tr>
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
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="4" class="text-center"><em>{{ lang._('No networks found') }}</em></td></tr>
                </tbody>
            </table>
        </div>
    </div>
</div>
