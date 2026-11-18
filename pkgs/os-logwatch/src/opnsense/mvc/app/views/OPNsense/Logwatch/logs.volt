{#
 # Copyright (C) 2026 Nils Stein
 # All rights reserved.
 #
 # OPNware os-logwatch — Live Syslog Viewer
 #}
<style>
    .ly-toolbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: flex-end; margin-bottom: 12px; }
    .ly-field { display: flex; flex-direction: column; gap: 3px; min-width: 130px; }
    .ly-field label { font-size: 11px; font-weight: 600; margin: 0; opacity: 0.8; text-transform: uppercase; }
    .ly-search-wrap { flex: 1 1 240px; min-width: 220px; }
    .ly-table-wrap { overflow-x: auto; border: 1px solid var(--bs-border-color, #ddd); border-radius: 3px; }
    #ly-log-table { margin-bottom: 0; table-layout: fixed; width: 100%; font-family: monospace; font-size: 12px; }
    #ly-log-table th { position: relative; user-select: none; white-space: nowrap; }
    #ly-log-table td { vertical-align: top; word-break: break-word; padding: 5px 7px; }
    .ly-col-resizer { position: absolute; top: 0; right: 0; width: 5px; height: 100%; cursor: col-resize; }
    .ly-col-resizer:hover { background: rgba(100, 150, 255, 0.45); }
    .ly-sev-emerg td, .ly-sev-alert td, .ly-sev-crit td { background-color: rgba(217, 83, 79, 0.16) !important; }
    .ly-sev-err td { background-color: rgba(217, 83, 79, 0.10) !important; }
    .ly-sev-warning td { background-color: rgba(240, 173, 78, 0.11) !important; }
    .ly-sev-notice td { background-color: rgba(91, 192, 222, 0.06) !important; }
    .ly-badge { display: inline-block; padding: 2px 6px; font-size: 10px; font-weight: 700; border-radius: 3px; text-transform: uppercase; color: #fff; }
    .ly-badge-emerg, .ly-badge-alert, .ly-badge-crit { background: #b52b27; }
    .ly-badge-err { background: #d9534f; }
    .ly-badge-warning { background: #e08e0b; }
    .ly-badge-notice { background: #31b0d5; }
    .ly-badge-info { background: #5cb85c; }
    .ly-badge-debug { background: #777; }
    .ly-actions-cell { white-space: nowrap; text-align: right; }
    .ly-status-strip { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; flex-wrap: wrap; gap: 8px; }
    .ly-btn-regex.active { background-color: #337ab7; color: #fff; border-color: #2e6da4; }
    .ly-btn-alert-hit { color: #e08e0b; border-color: #e08e0b; }
    .ly-toolbar .form-control,
    .ly-toolbar .btn { height: 28px; padding: 3px 8px; font-size: 12px; line-height: 1.4; }
    select.form-control,
    select.input-sm {
        height: 28px !important;
        padding: 0 24px 0 8px !important;
        font-size: 12px !important;
        line-height: 26px !important;
        vertical-align: middle;
    }
    .ly-modal .form-control { width: 100%; max-width: 100%; box-sizing: border-box; }
    .ly-modal .modal-body { padding: 15px; }
    .ly-modal .modal-footer { padding: 12px 15px; }
</style>

<script>
    $(document).ready(function () {
        const POLL_MS = 3000;
        const SEV_LEVELS = ['emerg', 'alert', 'crit', 'err', 'warning', 'notice', 'info', 'debug'];

        let paused = false;
        let regexMode = false;
        let pollTimer = null;
        let alertRules = [];
        let lastRows = [];
        let lastRowsSig = '';

        function escHtml(val) {
            return $('<div>').text(val === null || val === undefined ? '' : String(val)).html();
        }

        function escRegex(val) {
            return String(val || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        }

        function sevsAtOrAbove(level) {
            const idx = SEV_LEVELS.indexOf((level || '').toLowerCase());
            if (idx === -1) {
                return [level];
            }
            return SEV_LEVELS.slice(0, idx + 1);
        }

        function rowHitsAlert(row) {
            for (let i = 0; i < alertRules.length; i++) {
                const r = alertRules[i];
                if (r.host && row.host !== r.host) { continue; }
                if (r.facility && row.facility !== r.facility) { continue; }
                if (r.level) {
                    if (r.above) {
                        if (sevsAtOrAbove(r.level).indexOf(row.severity) === -1) { continue; }
                    } else if (row.severity !== r.level) {
                        continue;
                    }
                }
                if (r.tag) {
                    try {
                        if (!(new RegExp(r.tag)).test(row.tag || '')) { continue; }
                    } catch (e) { continue; }
                }
                if (r.message) {
                    try {
                        if (!(new RegExp(r.message)).test(row.message || '')) { continue; }
                    } catch (e) { continue; }
                }
                return r.name;
            }
            return null;
        }

        function timeBounds() {
            const preset = $('#ly-time-preset').val();
            const now = Math.floor(Date.now() / 1000);
            const map = { '5m': 300, '15m': 900, '1h': 3600, '6h': 21600, '24h': 86400, '7d': 604800 };
            if (map[preset]) {
                return { since: now - map[preset], until: 0 };
            }
            if (preset === 'custom') {
                const sRaw = $('#ly-since').val();
                const uRaw = $('#ly-until').val();
                return {
                    since: sRaw ? Math.floor(new Date(sRaw).getTime() / 1000) : 0,
                    until: uRaw ? Math.floor(new Date(uRaw).getTime() / 1000) : 0
                };
            }
            return { since: 0, until: 0 };
        }

        function currentQuery() {
            const bounds = timeBounds();
            return {
                host: $('#ly-host').val() || '',
                facility: $('#ly-facility').val() || '',
                severity: $('#ly-severity').val() || '',
                tag: $('#ly-tag').val() || '',
                search: $('#ly-search').val() || '',
                regex: regexMode ? '1' : '0',
                since: bounds.since,
                until: bounds.until,
                limit: $('#ly-limit').val() || '200',
                offset: 0
            };
        }

        function syncSelect($sel, values, defaultLabel) {
            const prev = $sel.val() || '';
            let html = '<option value="">' + escHtml(defaultLabel) + '</option>';
            for (let i = 0; i < values.length; i++) {
                html += '<option value="' + escHtml(values[i]) + '">' + escHtml(values[i]) + '</option>';
            }
            $sel.html(html);
            if (prev && values.indexOf(prev) !== -1) {
                $sel.val(prev);
            } else if (prev) {
                $sel.append('<option value="' + escHtml(prev) + '" selected>' + escHtml(prev) + '</option>');
            }
        }

        function loadFilters() {
            const q = currentQuery();
            $.getJSON('/api/logwatch/logs/filters', {
                host: q.host, facility: q.facility, severity: q.severity, tag: q.tag
            }, function (data) {
                if (!data || data.status !== 'ok') {
                    return;
                }
                syncSelect($('#ly-host'), data.hosts || [], '{{ lang._("All Hosts") }}');
                syncSelect($('#ly-facility'), data.facilities || [], '{{ lang._("All Facilities") }}');
                syncSelect($('#ly-tag'), data.tags || [], '{{ lang._("All Tags") }}');
            });
        }

        function renderRows(rows) {
            const sig = JSON.stringify(rows || []);
            if (sig === lastRowsSig) {
                return;
            }
            lastRowsSig = sig;
            lastRows = rows || [];
            if (!lastRows.length) {
                $('#ly-log-body').html('<tr><td colspan="7" class="text-center text-muted" style="padding: 18px;">{{ lang._("No matching log entries.") }}</td></tr>');
                return;
            }

            let html = '';
            for (let i = 0; i < lastRows.length; i++) {
                const r = lastRows[i];
                const hitRule = rowHitsAlert(r);
                const ignCls = hitRule ? 'btn-default ly-btn-alert-hit' : 'btn-default';
                const ignTitle = hitRule
                    ? '{{ lang._("Matches alert rule:") }} ' + escHtml(hitRule) + ' — {{ lang._("Click to ignore or discard") }}'
                    : '{{ lang._("Ignore / Discard matching logs") }}';

                html += '<tr class="ly-sev-' + escHtml(r.severity) + '">' +
                    '<td style="white-space:nowrap;">' + escHtml(r.timestamp) + '</td>' +
                    '<td>' + escHtml(r.host) + '</td>' +
                    '<td>' + escHtml(r.facility) + '</td>' +
                    '<td><span class="ly-badge ly-badge-' + escHtml(r.severity) + '">' + escHtml(r.severity) + '</span></td>' +
                    '<td>' + escHtml(r.tag) + '</td>' +
                    '<td>' + escHtml(r.message) + '</td>' +
                    '<td class="ly-actions-cell">' +
                    '<button type="button" class="btn btn-xs btn-default ly-copy-btn" data-idx="' + i + '" title="{{ lang._("Copy log line") }}"><i class="fa fa-clipboard"></i></button> ' +
                    '<button type="button" class="btn btn-xs ' + ignCls + ' ly-ignore-btn" data-idx="' + i + '" title="' + ignTitle + '"><i class="fa fa-bell-slash"></i></button>' +
                    '</td></tr>';
            }
            $('#ly-log-body').html(html);
        }

        function loadLogs() {
            const q = currentQuery();
            $.getJSON('/api/logwatch/logs/query', q, function (data) {
                if (!data || data.status !== 'ok') {
                    $('#ly-query-error').text((data && data.message) || '{{ lang._("Query failed") }}').show();
                    return;
                }
                $('#ly-query-error').hide();
                alertRules = data.alert_rules || [];
                renderRows(data.rows || []);
                const mb = ((data.db_size_bytes || 0) / (1024 * 1024)).toFixed(2);
                $('#ly-stats-badge').text((data.rows ? data.rows.length : 0) + ' / ' + (data.total || 0) + ' {{ lang._("matches") }} | ' + mb + ' MB');
            });
        }

        function restartPoll() {
            if (pollTimer) {
                clearInterval(pollTimer);
                pollTimer = null;
            }
            if (!paused) {
                pollTimer = setInterval(function () {
                    loadLogs();
                    loadFilters();
                }, POLL_MS);
            }
        }

        function initResizers() {
            $('#ly-log-table th').each(function () {
                const $th = $(this);
                if ($th.hasClass('ly-no-resize')) {
                    return;
                }
                const $resizer = $('<div class="ly-col-resizer"></div>');
                $th.append($resizer);
                $resizer.on('mousedown', function (e) {
                    e.preventDefault();
                    const startX = e.pageX;
                    const startW = $th.width();
                    $(document).on('mousemove.lyresize', function (ev) {
                        const newW = Math.max(55, startW + (ev.pageX - startX));
                        $th.width(newW);
                    });
                    $(document).on('mouseup.lyresize', function () {
                        $(document).off('.lyresize');
                    });
                });
            });
        }

        // Hydrate initial filters from URL query params (e.g. from Lobby Dashboard widget)
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.get('severity')) {
            $('#ly-severity').val(urlParams.get('severity'));
        }
        if (urlParams.get('preset')) {
            $('#ly-time-preset').val(urlParams.get('preset'));
        }
        if (urlParams.get('host')) {
            syncSelect($('#ly-host'), [urlParams.get('host')], '{{ lang._("All Hosts") }}');
            $('#ly-host').val(urlParams.get('host'));
        }

        $('#ly-host, #ly-facility, #ly-severity, #ly-tag, #ly-limit').on('change', function () {
            loadFilters();
            loadLogs();
        });

        $('#ly-time-preset').on('change', function () {
            if ($(this).val() === 'custom') {
                $('#ly-custom-range').show();
            } else {
                $('#ly-custom-range').hide();
                loadLogs();
            }
        });

        $('#ly-apply-custom').on('click', loadLogs);

        let searchTimer = null;
        $('#ly-search').on('input', function () {
            clearTimeout(searchTimer);
            searchTimer = setTimeout(loadLogs, 220);
        });

        $('#ly-regex-toggle').on('click', function () {
            regexMode = !regexMode;
            $(this).toggleClass('active', regexMode);
            loadLogs();
        });

        $('#ly-refresh-btn').on('click', function () {
            loadFilters();
            loadLogs();
        });

        $('#ly-pause-btn').on('click', function () {
            paused = !paused;
            if (paused) {
                $(this).removeClass('btn-default').addClass('btn-warning').html('<i class="fa fa-play"></i> {{ lang._("Paused") }}');
            } else {
                $(this).removeClass('btn-warning').addClass('btn-default').html('<i class="fa fa-pause"></i> {{ lang._("Live") }}');
                loadLogs();
            }
            restartPoll();
        });

        $('#ly-clear-btn').on('click', function () {
            BootstrapDialog.confirm({
                title: '{{ lang._("Clear Log Database") }}',
                message: '{{ lang._("Delete all stored logs from the Logwatch SQLite database? This cannot be undone.") }}',
                type: BootstrapDialog.TYPE_DANGER,
                btnOKLabel: '{{ lang._("Clear All") }}',
                callback: function (ok) {
                    if (!ok) {
                        return;
                    }
                    ajaxCall('/api/logwatch/logs/clear', {}, function () {
                        loadFilters();
                        loadLogs();
                    });
                }
            });
        });

        $('#ly-log-body').on('click', '.ly-copy-btn', function () {
            const row = lastRows[$(this).data('idx')];
            if (!row) {
                return;
            }
            const txt = row.timestamp + ' ' + row.host + ' ' + row.facility + '.' + row.severity + ' ' + row.tag + ': ' + row.message;
            const $icon = $(this).find('i');
            if (navigator.clipboard) {
                navigator.clipboard.writeText(txt).then(function () {
                    $icon.removeClass('fa-clipboard').addClass('fa-check text-success');
                    setTimeout(function () {
                        $icon.removeClass('fa-check text-success').addClass('fa-clipboard');
                    }, 1500);
                });
            }
        });

        $('#ly-log-body').on('click', '.ly-ignore-btn', function () {
            const row = lastRows[$(this).data('idx')];
            if (!row) {
                return;
            }
            $('#ign-host').val(row.host || '');
            $('#ign-facility').val(row.facility || '');
            $('#ign-level').val(row.severity || '');
            $('#ign-tag').val(escRegex(row.tag || ''));
            $('#ign-message').val(escRegex(row.message || ''));
            $('#ign-mode-suppress').prop('checked', true);
            $('#ign-error').hide();
            $('#modal-add-ignore').modal('show');
        });

        $('#ign-save-btn').on('click', function () {
            const discard = $('input[name="ign-mode"]:checked').val() === '1';
            const $btn = $(this).prop('disabled', true);
            $.post('/api/logwatch/logs/addIgnore', {
                host: $('#ign-host').val(),
                facility: $('#ign-facility').val(),
                level: $('#ign-level').val(),
                tag: $('#ign-tag').val(),
                message: $('#ign-message').val(),
                discard: discard ? '1' : '0'
            }, function (res) {
                $btn.prop('disabled', false);
                if (!res || res.status !== 'ok') {
                    $('#ign-error').text((res && res.message) || '{{ lang._("Failed to save rule") }}').show();
                    return;
                }
                $('#modal-add-ignore').modal('hide');
                loadLogs();
            }).fail(function () {
                $btn.prop('disabled', false);
                $('#ign-error').text('{{ lang._("Request failed") }}').show();
            });
        });

        updateServiceControlUI('logwatch');
        initResizers();
        loadFilters();
        loadLogs();
        restartPoll();
    });
</script>

<div class="content-box" style="padding: 15px;">
    <div class="ly-status-strip">
        <div>
            <span class="label label-default" id="ly-stats-badge">--</span>
            <span id="ly-query-error" class="text-danger" style="display:none; margin-left: 10px; font-weight: bold;"></span>
        </div>
        <div class="btn-group btn-group-sm">
            <button type="button" id="ly-pause-btn" class="btn btn-default"><i class="fa fa-pause"></i> {{ lang._('Live') }}</button>
            <button type="button" id="ly-refresh-btn" class="btn btn-default"><i class="fa fa-refresh"></i> {{ lang._('Refresh') }}</button>
            <button type="button" id="ly-clear-btn" class="btn btn-danger"><i class="fa fa-trash"></i> {{ lang._('Clear DB') }}</button>
        </div>
    </div>

    <div class="ly-toolbar">
        <div class="ly-field">
            <label for="ly-host">{{ lang._('Host') }}</label>
            <select id="ly-host" class="form-control input-sm"><option value="">{{ lang._('All Hosts') }}</option></select>
        </div>
        <div class="ly-field">
            <label for="ly-facility">{{ lang._('Facility') }}</label>
            <select id="ly-facility" class="form-control input-sm"><option value="">{{ lang._('All Facilities') }}</option></select>
        </div>
        <div class="ly-field">
            <label for="ly-severity">{{ lang._('Severity (>=)') }}</label>
            <select id="ly-severity" class="form-control input-sm">
                <option value="">{{ lang._('All Severities') }}</option>
                <option value="emerg">emerg</option>
                <option value="alert">alert</option>
                <option value="crit">crit</option>
                <option value="err">err</option>
                <option value="warning">warning</option>
                <option value="notice">notice</option>
                <option value="info">info</option>
                <option value="debug">debug</option>
            </select>
        </div>
        <div class="ly-field">
            <label for="ly-tag">{{ lang._('Tag') }}</label>
            <select id="ly-tag" class="form-control input-sm"><option value="">{{ lang._('All Tags') }}</option></select>
        </div>
        <div class="ly-field">
            <label for="ly-time-preset">{{ lang._('Time Range') }}</label>
            <select id="ly-time-preset" class="form-control input-sm">
                <option value="5m" selected>{{ lang._('Last 5 min') }}</option>
                <option value="15m">{{ lang._('Last 15 min') }}</option>
                <option value="1h">{{ lang._('Last 1 hour') }}</option>
                <option value="6h">{{ lang._('Last 6 hours') }}</option>
                <option value="24h">{{ lang._('Last 24 hours') }}</option>
                <option value="7d">{{ lang._('Last 7 days') }}</option>
                <option value="all">{{ lang._('All time') }}</option>
                <option value="custom">{{ lang._('Custom range') }}</option>
            </select>
        </div>
        <div class="ly-field" style="min-width: 95px;">
            <label for="ly-limit">{{ lang._('Limit') }}</label>
            <select id="ly-limit" class="form-control input-sm">
                <option value="200" selected>200</option>
                <option value="500">500</option>
                <option value="1000">1000</option>
                <option value="5000">5000</option>
                <option value="0">{{ lang._('Unlimited') }}</option>
            </select>
        </div>
        <div class="ly-field ly-search-wrap">
            <label for="ly-search">{{ lang._('Search') }}</label>
            <div class="input-group input-group-sm">
                <input type="text" id="ly-search" class="form-control" placeholder="{{ lang._('Filter message, tag, or host...') }}">
                <span class="input-group-btn">
                    <button type="button" id="ly-regex-toggle" class="btn btn-default ly-btn-regex" title="{{ lang._('Toggle Regular Expression search') }}">.*</button>
                </span>
            </div>
        </div>
    </div>

    <div id="ly-custom-range" class="ly-toolbar" style="display:none;">
        <div class="ly-field">
            <label for="ly-since">{{ lang._('Start') }}</label>
            <input type="datetime-local" id="ly-since" class="form-control input-sm">
        </div>
        <div class="ly-field">
            <label for="ly-until">{{ lang._('End') }}</label>
            <input type="datetime-local" id="ly-until" class="form-control input-sm">
        </div>
        <button type="button" id="ly-apply-custom" class="btn btn-primary btn-sm">{{ lang._('Apply Range') }}</button>
    </div>

    <div class="ly-table-wrap">
        <table class="table table-striped table-condensed table-hover" id="ly-log-table">
            <thead>
                <tr>
                    <th style="width: 150px;">{{ lang._('Timestamp') }}</th>
                    <th style="width: 140px;">{{ lang._('Host') }}</th>
                    <th style="width: 85px;">{{ lang._('Facility') }}</th>
                    <th style="width: 85px;">{{ lang._('Severity') }}</th>
                    <th style="width: 120px;">{{ lang._('Tag') }}</th>
                    <th>{{ lang._('Message') }}</th>
                    <th class="ly-no-resize" style="width: 72px; text-align:right;">{{ lang._('Actions') }}</th>
                </tr>
            </thead>
            <tbody id="ly-log-body">
                <tr><td colspan="7" class="text-center"><i class="fa fa-spinner fa-pulse"></i> {{ lang._('Loading logs...') }}</td></tr>
            </tbody>
        </table>
    </div>
</div>

<!-- 1-Click Ignore / Discard Modal -->
<div class="modal fade ly-modal" id="modal-add-ignore" tabindex="-1" role="dialog">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal"><span>&times;</span></button>
                <h4 class="modal-title" style="margin-top:0;"><i class="fa fa-bell-slash"></i> {{ lang._('Add Ignore / Discard Rule') }}</h4>
            </div>
            <div class="modal-body">
                <div class="alert alert-danger" id="ign-error" style="display:none;"></div>
                <div class="form-group">
                    <label>{{ lang._('Action Mode') }}</label>
                    <div>
                        <label class="radio-inline"><input type="radio" name="ign-mode" id="ign-mode-suppress" value="0" checked> {{ lang._('Suppress Alerts Only (keep in DB)') }}</label>
                        <label class="radio-inline"><input type="radio" name="ign-mode" id="ign-mode-discard" value="1"> {{ lang._('Discard at Ingest (drop before DB)') }}</label>
                    </div>
                </div>
                <div class="row">
                    <div class="col-sm-6"><div class="form-group">
                        <label>{{ lang._('Host (exact)') }}</label>
                        <input type="text" id="ign-host" class="form-control input-sm">
                    </div></div>
                    <div class="col-sm-6"><div class="form-group">
                        <label>{{ lang._('Facility (exact)') }}</label>
                        <input type="text" id="ign-facility" class="form-control input-sm">
                    </div></div>
                </div>
                <div class="row">
                    <div class="col-sm-6"><div class="form-group">
                        <label>{{ lang._('Level (exact)') }}</label>
                        <select id="ign-level" class="form-control input-sm">
                            <option value="">{{ lang._('Any') }}</option>
                            <option value="emerg">emerg</option>
                            <option value="alert">alert</option>
                            <option value="crit">crit</option>
                            <option value="err">err</option>
                            <option value="warning">warning</option>
                            <option value="notice">notice</option>
                            <option value="info">info</option>
                            <option value="debug">debug</option>
                        </select>
                    </div></div>
                    <div class="col-sm-6"><div class="form-group">
                        <label>{{ lang._('Tag (regex)') }}</label>
                        <input type="text" id="ign-tag" class="form-control input-sm">
                    </div></div>
                </div>
                <div class="form-group">
                    <label>{{ lang._('Message (regex)') }}</label>
                    <textarea id="ign-message" class="form-control input-sm" rows="3" style="font-family: monospace;"></textarea>
                    <span class="help-block">{{ lang._('Clear any field to match any value. Tag and Message support RE2/Python regex.') }}</span>
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Cancel') }}</button>
                <button type="button" class="btn btn-primary" id="ign-save-btn">{{ lang._('Save Rule') }}</button>
            </div>
        </div>
    </div>
</div>
