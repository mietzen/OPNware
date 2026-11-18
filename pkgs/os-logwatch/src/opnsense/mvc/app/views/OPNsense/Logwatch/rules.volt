{#
 # Copyright (C) 2026 Nils Stein
 # All rights reserved.
 #
 # OPNware os-logwatch — Rules, Alerts, Digest & Monaco YAML Editor
 #}
<style>
    .opnware-logwatch-tabs { margin-bottom: 0; }
    .opnware-logwatch-content { padding: 0 15px 15px; }
    .opnware-logwatch-content > .tab-pane { padding-top: 15px; }
    .opnware-logwatch-content h3, .opnware-logwatch-content h4 { margin-top: 0; }
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

<script src="/ui/js/vendor/monaco/vs/loader.js"></script>
<script>
    require.config({
        paths: { vs: '/ui/js/vendor/monaco/vs' }
    });

    $(document).ready(function () {
        window.scrollTo(0, 0);

        let rulesModel = { alerts: [], ignore: [], severity_rewrite: [], digest: { enabled: false, initial: '5m', multiplier: 3, max: '2h', cooldown: '10m' } };
        let alertStates = {};
        let editor = null;
        let editAlertIdx = -1;
        let editIgnoreIdx = -1;
        let editRewriteIdx = -1;

        let wordWrap = window.localStorage.getItem('opnware-editor-wrap') || 'on';
        let minimap = (window.localStorage.getItem('opnware-editor-minimap') === 'true');
        let fontSize = parseInt(window.localStorage.getItem('opnware-editor-fontsize') || '13', 10);

        function escHtml(v) {
            return $('<div>').text(v === null || v === undefined ? '' : String(v)).html();
        }

        function fmtTime(epoch) {
            if (!epoch || epoch <= 0) {
                return '<span class="text-muted">{{ lang._("Never") }}</span>';
            }
            return new Date(epoch * 1000).toLocaleString();
        }

        function fmtMatchers(r) {
            const parts = [];
            if (r.host) { parts.push('host=<code>' + escHtml(r.host) + '</code>'); }
            if (r.facility) { parts.push('fac=<code>' + escHtml(r.facility) + '</code>'); }
            if (r.tag) { parts.push('tag~<code>' + escHtml(r.tag) + '</code>'); }
            if (r.message) { parts.push('msg~<code>' + escHtml(r.message) + '</code>'); }
            return parts.length ? parts.join(' &middot; ') : '<em class="text-muted">{{ lang._("Any") }}</em>';
        }

        function showBanner(ok, msg) {
            const $b = $('#rules-feedback');
            $b.removeClass('alert-success alert-danger')
                .addClass(ok ? 'alert-success' : 'alert-danger')
                .text(msg)
                .show();
            if (ok) {
                setTimeout(function () { $b.fadeOut(); }, 3500);
            }
        }

        function saveParsed() {
            $.post('/api/logwatch/rules/save', { parsed: JSON.stringify(rulesModel) }, function (res) {
                if (!res || res.status !== 'ok') {
                    showBanner(false, (res && res.message) || '{{ lang._("Validation error") }}');
                    return;
                }
                if (res.parsed) {
                    rulesModel = res.parsed;
                }
                if (editor && res.yaml !== undefined) {
                    editor.setValue(res.yaml);
                }
                renderAll();
                showBanner(true, res.message || '{{ lang._("Saved") }}');
            });
        }

        function renderAlerts() {
            const list = rulesModel.alerts || [];
            if (!list.length) {
                $('#tbl-alerts tbody').html('<tr><td colspan="6" class="text-center text-muted">{{ lang._("No alert rules defined.") }}</td></tr>');
                return;
            }
            let html = '';
            for (let i = 0; i < list.length; i++) {
                const r = list[i];
                const st = alertStates[r.name] || {};
                const lvlBadge = '<code>' + escHtml(r.level) + (r.above ? '+' : '') + '</code>';
                html += '<tr>' +
                    '<td><b>' + escHtml(r.name) + '</b></td>' +
                    '<td>' + escHtml(r.count) + ' in ' + escHtml(r.window_minutes) + 'm</td>' +
                    '<td>' + lvlBadge + '</td>' +
                    '<td>' + fmtMatchers(r) + '</td>' +
                    '<td>' + fmtTime(st.last_alerted_at) + (st.last_count ? ' <span class="badge">' + escHtml(st.last_count) + '</span>' : '') + '</td>' +
                    '<td style="white-space:nowrap; text-align:right;">' +
                    '<button class="btn btn-xs btn-default btn-edit-alert" data-idx="' + i + '" title="{{ lang._("Edit") }}"><i class="fa fa-pencil"></i></button> ' +
                    '<button class="btn btn-xs btn-default btn-reset-one" data-name="' + escHtml(r.name) + '" title="{{ lang._("Reset Cooldown") }}"><i class="fa fa-history"></i></button> ' +
                    '<button class="btn btn-xs btn-danger btn-del-alert" data-idx="' + i + '" title="{{ lang._("Delete") }}"><i class="fa fa-trash"></i></button>' +
                    '</td></tr>';
            }
            $('#tbl-alerts tbody').html(html);
        }

        function renderIgnores() {
            const list = rulesModel.ignore || [];
            if (!list.length) {
                $('#tbl-ignores tbody').html('<tr><td colspan="5" class="text-center text-muted">{{ lang._("No ignore rules defined.") }}</td></tr>');
                return;
            }
            let html = '';
            for (let i = 0; i < list.length; i++) {
                const r = list[i];
                const badge = r.discard
                    ? '<span class="label label-danger">{{ lang._("Discard at Ingest") }}</span>'
                    : '<span class="label label-warning">{{ lang._("Suppress Alerts") }}</span>';
                html += '<tr>' +
                    '<td>' + badge + '</td>' +
                    '<td>' + (r.level ? '<code>' + escHtml(r.level) + '</code>' : '<em class="text-muted">*</em>') + '</td>' +
                    '<td>' + fmtMatchers(r) + '</td>' +
                    '<td style="white-space:nowrap; text-align:right;">' +
                    '<button class="btn btn-xs btn-default btn-edit-ignore" data-idx="' + i + '" title="{{ lang._("Edit") }}"><i class="fa fa-pencil"></i></button> ' +
                    '<button class="btn btn-xs btn-danger btn-del-ignore" data-idx="' + i + '" title="{{ lang._("Delete") }}"><i class="fa fa-trash"></i></button>' +
                    '</td></tr>';
            }
            $('#tbl-ignores tbody').html(html);
        }

        function renderRewrites() {
            const list = rulesModel.severity_rewrite || [];
            if (!list.length) {
                $('#tbl-rewrites tbody').html('<tr><td colspan="5" class="text-center text-muted">{{ lang._("No severity rewrite rules defined.") }}</td></tr>');
                return;
            }
            let html = '';
            for (let i = 0; i < list.length; i++) {
                const r = list[i];
                html += '<tr>' +
                    '<td>' + (i + 1) + '</td>' +
                    '<td>' + (r.level ? '<code>' + escHtml(r.level) + '</code>' : '<em class="text-muted">*</em>') + '</td>' +
                    '<td>' + fmtMatchers(r) + '</td>' +
                    '<td><span class="label label-info">' + escHtml(r.new_severity) + '</span></td>' +
                    '<td style="white-space:nowrap; text-align:right;">' +
                    '<button class="btn btn-xs btn-default btn-up-rw" data-idx="' + i + '" ' + (i === 0 ? 'disabled' : '') + '><i class="fa fa-arrow-up"></i></button> ' +
                    '<button class="btn btn-xs btn-default btn-dn-rw" data-idx="' + i + '" ' + (i === list.length - 1 ? 'disabled' : '') + '><i class="fa fa-arrow-down"></i></button> ' +
                    '<button class="btn btn-xs btn-default btn-edit-rw" data-idx="' + i + '"><i class="fa fa-pencil"></i></button> ' +
                    '<button class="btn btn-xs btn-danger btn-del-rw" data-idx="' + i + '"><i class="fa fa-trash"></i></button>' +
                    '</td></tr>';
            }
            $('#tbl-rewrites tbody').html(html);
        }

        function renderDigest() {
            const d = rulesModel.digest || {};
            $('#dig-enabled').prop('checked', !!d.enabled);
            $('#dig-initial').val(d.initial || '5m');
            $('#dig-multiplier').val(d.multiplier || 3);
            $('#dig-max').val(d.max || '2h');
            $('#dig-cooldown').val(d.cooldown || '10m');
        }

        function renderAll() {
            renderAlerts();
            renderIgnores();
            renderRewrites();
            renderDigest();
        }

        function loadAlertState() {
            $.getJSON('/api/logwatch/rules/alertState', function (res) {
                if (!res || res.status !== 'ok') {
                    return;
                }
                alertStates = {};
                (res.rules || []).forEach(function (r) {
                    alertStates[r.name] = r;
                });
                const d = res.digest || {};
                $('#dig-queued').text(d.queued_count || 0);
                $('#dig-window').text(d.window_sec ? (d.window_sec + 's') : '{{ lang._("Initial") }}');
                $('#dig-next-flush').html(fmtTime(d.next_flush));
                $('#dig-last-sent').html(fmtTime(d.last_sent));
                renderAlerts();
            });
        }

        function loadRules() {
            $.getJSON('/api/logwatch/rules/get', function (res) {
                if (!res || res.status !== 'ok') {
                    showBanner(false, (res && res.message) || '{{ lang._("Failed to load rules") }}');
                    return;
                }
                if (res.parsed) {
                    rulesModel = res.parsed;
                }
                if (editor && res.yaml !== undefined) {
                    editor.setValue(res.yaml);
                }
                if (res.warning) {
                    showBanner(false, res.warning);
                }
                renderAll();
                loadAlertState();
            });
        }

        // Alert Modal Handlers
        $('#btn-add-alert').on('click', function () {
            editAlertIdx = -1;
            $('#al-name, #al-host, #al-facility, #al-tag, #al-message').val('');
            $('#al-count').val(5);
            $('#al-window').val(5);
            $('#al-level').val('err');
            $('#al-above').prop('checked', true);
            $('#modal-alert').modal('show');
        });

        $('#tbl-alerts').on('click', '.btn-edit-alert', function () {
            editAlertIdx = $(this).data('idx');
            const r = rulesModel.alerts[editAlertIdx];
            $('#al-name').val(r.name || '');
            $('#al-count').val(r.count || 1);
            $('#al-window').val(r.window_minutes || 5);
            $('#al-level').val(r.level || 'err');
            $('#al-above').prop('checked', !!r.above);
            $('#al-host').val(r.host || '');
            $('#al-facility').val(r.facility || '');
            $('#al-tag').val(r.tag || '');
            $('#al-message').val(r.message || '');
            $('#modal-alert').modal('show');
        });

        $('#al-save-btn').on('click', function () {
            const obj = {
                name: $('#al-name').val().trim(),
                count: parseInt($('#al-count').val() || '1', 10),
                window_minutes: parseInt($('#al-window').val() || '5', 10),
                level: $('#al-level').val(),
                above: $('#al-above').is(':checked')
            };
            ['host', 'facility', 'tag', 'message'].forEach(function (k) {
                const v = $('#al-' + k).val().trim();
                if (v) { obj[k] = v; }
            });
            if (editAlertIdx >= 0) {
                rulesModel.alerts[editAlertIdx] = obj;
            } else {
                rulesModel.alerts.push(obj);
            }
            $('#modal-alert').modal('hide');
            saveParsed();
        });

        $('#tbl-alerts').on('click', '.btn-del-alert', function () {
            rulesModel.alerts.splice($(this).data('idx'), 1);
            saveParsed();
        });

        $('#tbl-alerts').on('click', '.btn-reset-one', function () {
            const name = $(this).data('name');
            $.post('/api/logwatch/rules/resetCooldown', { rule_name: name }, function () {
                loadAlertState();
                showBanner(true, '{{ lang._("Cooldown reset for ") }}' + name);
            });
        });

        $('#btn-reset-all-cooldowns').on('click', function () {
            $.post('/api/logwatch/rules/resetCooldown', { clear_digest: '1' }, function () {
                loadAlertState();
                showBanner(true, '{{ lang._("All cooldowns and digest queue cleared.") }}');
            });
        });

        // Ignore Modal Handlers
        $('#btn-add-ignore').on('click', function () {
            editIgnoreIdx = -1;
            $('#ir-host, #ir-facility, #ir-tag, #ir-message').val('');
            $('#ir-level').val('');
            $('#ir-discard').prop('checked', false);
            $('#modal-ignore').modal('show');
        });

        $('#tbl-ignores').on('click', '.btn-edit-ignore', function () {
            editIgnoreIdx = $(this).data('idx');
            const r = rulesModel.ignore[editIgnoreIdx];
            $('#ir-host').val(r.host || '');
            $('#ir-facility').val(r.facility || '');
            $('#ir-level').val(r.level || '');
            $('#ir-tag').val(r.tag || '');
            $('#ir-message').val(r.message || '');
            $('#ir-discard').prop('checked', !!r.discard);
            $('#modal-ignore').modal('show');
        });

        $('#ir-save-btn').on('click', function () {
            const obj = { discard: $('#ir-discard').is(':checked') };
            ['host', 'facility', 'level', 'tag', 'message'].forEach(function (k) {
                const v = $('#ir-' + k).val().trim();
                if (v) { obj[k] = v; }
            });
            if (editIgnoreIdx >= 0) {
                rulesModel.ignore[editIgnoreIdx] = obj;
            } else {
                rulesModel.ignore.push(obj);
            }
            $('#modal-ignore').modal('hide');
            saveParsed();
        });

        $('#tbl-ignores').on('click', '.btn-del-ignore', function () {
            rulesModel.ignore.splice($(this).data('idx'), 1);
            saveParsed();
        });

        // Rewrite Modal & Order Handlers
        $('#btn-add-rewrite').on('click', function () {
            editRewriteIdx = -1;
            $('#rw-host, #rw-facility, #rw-tag, #rw-message').val('');
            $('#rw-level').val('');
            $('#rw-new-sev').val('err');
            $('#modal-rewrite').modal('show');
        });

        $('#tbl-rewrites').on('click', '.btn-edit-rw', function () {
            editRewriteIdx = $(this).data('idx');
            const r = rulesModel.severity_rewrite[editRewriteIdx];
            $('#rw-host').val(r.host || '');
            $('#rw-facility').val(r.facility || '');
            $('#rw-level').val(r.level || '');
            $('#rw-tag').val(r.tag || '');
            $('#rw-message').val(r.message || '');
            $('#rw-new-sev').val(r.new_severity || 'err');
            $('#modal-rewrite').modal('show');
        });

        $('#rw-save-btn').on('click', function () {
            const obj = { new_severity: $('#rw-new-sev').val() };
            ['host', 'facility', 'level', 'tag', 'message'].forEach(function (k) {
                const v = $('#rw-' + k).val().trim();
                if (v) { obj[k] = v; }
            });
            if (editRewriteIdx >= 0) {
                rulesModel.severity_rewrite[editRewriteIdx] = obj;
            } else {
                rulesModel.severity_rewrite.push(obj);
            }
            $('#modal-rewrite').modal('hide');
            saveParsed();
        });

        $('#tbl-rewrites').on('click', '.btn-del-rw', function () {
            rulesModel.severity_rewrite.splice($(this).data('idx'), 1);
            saveParsed();
        });

        $('#tbl-rewrites').on('click', '.btn-up-rw', function () {
            const i = $(this).data('idx');
            if (i <= 0) { return; }
            const tmp = rulesModel.severity_rewrite[i - 1];
            rulesModel.severity_rewrite[i - 1] = rulesModel.severity_rewrite[i];
            rulesModel.severity_rewrite[i] = tmp;
            saveParsed();
        });

        $('#tbl-rewrites').on('click', '.btn-dn-rw', function () {
            const i = $(this).data('idx');
            if (i >= rulesModel.severity_rewrite.length - 1) { return; }
            const tmp = rulesModel.severity_rewrite[i + 1];
            rulesModel.severity_rewrite[i + 1] = rulesModel.severity_rewrite[i];
            rulesModel.severity_rewrite[i] = tmp;
            saveParsed();
        });

        // Digest Save & Reset
        $('#btn-save-digest').on('click', function () {
            rulesModel.digest = {
                enabled: $('#dig-enabled').is(':checked'),
                initial: $('#dig-initial').val().trim() || '5m',
                multiplier: parseFloat($('#dig-multiplier').val() || '3'),
                max: $('#dig-max').val().trim() || '2h',
                cooldown: $('#dig-cooldown').val().trim() || '10m'
            };
            saveParsed();
        });

        // Monaco YAML Editor
        function preferredTheme() {
            const saved = window.localStorage.getItem('opnware-logwatch-editor-theme');
            if (saved === 'vs' || saved === 'vs-dark') {
                return saved;
            }
            return (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'vs-dark' : 'vs';
        }

        function syncTheme() {
            if (!editor || !window.opnwareLogwatchMonaco) {
                return;
            }
            const th = preferredTheme();
            window.opnwareLogwatchMonaco.editor.setTheme(th);
            $('#ly-theme-icon').toggleClass('fa-sun-o', th === 'vs-dark').toggleClass('fa-moon-o', th !== 'vs-dark');
        }

        require(['vs/editor/editor.main', 'vs/basic-languages/monaco.contribution'], function (monaco) {
            window.opnwareLogwatchMonaco = monaco;
            editor = monaco.editor.create(document.getElementById('ly-yaml-editor'), {
                value: '',
                language: 'yaml',
                theme: preferredTheme(),
                automaticLayout: true,
                minimap: { enabled: minimap },
                fontSize: fontSize,
                tabSize: 2,
                wordWrap: wordWrap,
                scrollBeyondLastLine: false,
                lineNumbersMinChars: 3
            });
            editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function () {
                $('#btn-save-yaml').click();
            });
            syncTheme();
            loadRules();
        });

        $('a[href="#tab-yaml"]').on('shown.bs.tab', function () {
            if (editor) {
                editor.layout();
            }
        });

        $('#btn-yaml-wrap').on('click', function () {
            wordWrap = (wordWrap === 'on') ? 'off' : 'on';
            window.localStorage.setItem('opnware-editor-wrap', wordWrap);
            if (editor) { editor.updateOptions({ wordWrap: wordWrap }); }
            $(this).toggleClass('active', wordWrap === 'on');
        }).toggleClass('active', wordWrap === 'on');

        $('#btn-yaml-minimap').on('click', function () {
            minimap = !minimap;
            window.localStorage.setItem('opnware-editor-minimap', minimap ? 'true' : 'false');
            if (editor) { editor.updateOptions({ minimap: { enabled: minimap } }); }
            $(this).toggleClass('active', minimap);
        }).toggleClass('active', minimap);

        $('#btn-yaml-font-dec').on('click', function () {
            if (fontSize > 9) {
                fontSize--;
                window.localStorage.setItem('opnware-editor-fontsize', fontSize);
                if (editor) { editor.updateOptions({ fontSize: fontSize }); }
            }
        });

        $('#btn-yaml-font-inc').on('click', function () {
            if (fontSize < 24) {
                fontSize++;
                window.localStorage.setItem('opnware-editor-fontsize', fontSize);
                if (editor) { editor.updateOptions({ fontSize: fontSize }); }
            }
        });

        $('#btn-yaml-theme').on('click', function () {
            const next = (preferredTheme() === 'vs-dark') ? 'vs' : 'vs-dark';
            window.localStorage.setItem('opnware-logwatch-editor-theme', next);
            syncTheme();
        });

        $('#btn-save-yaml').on('click', function () {
            const yamlText = editor ? editor.getValue() : '';
            $.post('/api/logwatch/rules/save', { yaml: yamlText }, function (res) {
                if (!res || res.status !== 'ok') {
                    showBanner(false, (res && res.message) || '{{ lang._("YAML validation failed") }}');
                    return;
                }
                if (res.parsed) { rulesModel = res.parsed; }
                if (editor && res.yaml !== undefined) { editor.setValue(res.yaml); }
                renderAll();
                showBanner(true, res.message || '{{ lang._("YAML saved and applied") }}');
            });
        });

        updateServiceControlUI('logwatch');
    });
</script>

<div id="rules-feedback" class="alert" style="display:none; margin-bottom: 12px;"></div>

<ul class="nav nav-tabs opnware-logwatch-tabs" role="tablist">
    <li class="active"><a href="#tab-alerts" data-toggle="tab"><i class="fa fa-bell"></i> {{ lang._('Alert Rules') }}</a></li>
    <li><a href="#tab-ignores" data-toggle="tab"><i class="fa fa-bell-slash"></i> {{ lang._('Ignore & Discard') }}</a></li>
    <li><a href="#tab-rewrites" data-toggle="tab"><i class="fa fa-exchange"></i> {{ lang._('Severity Rewrites') }}</a></li>
    <li><a href="#tab-digest" data-toggle="tab"><i class="fa fa-clock-o"></i> {{ lang._('Digest Escalation') }}</a></li>
    <li><a href="#tab-yaml" data-toggle="tab"><i class="fa fa-code"></i> {{ lang._('YAML Editor') }}</a></li>
</ul>

<div class="content-box tab-content opnware-logwatch-content">
    <!-- Tab 1: Alert Rules -->
    <div id="tab-alerts" class="tab-pane active">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
            <h4 style="margin:0;">{{ lang._('Alert Rules & Cooldown State') }}</h4>
            <div>
                <button type="button" id="btn-reset-all-cooldowns" class="btn btn-default btn-sm"><i class="fa fa-history"></i> {{ lang._('Reset All Cooldowns') }}</button>
                <button type="button" id="btn-add-alert" class="btn btn-primary btn-sm"><i class="fa fa-plus"></i> {{ lang._('Add Alert Rule') }}</button>
            </div>
        </div>
        <div class="table-responsive">
            <table class="table table-striped table-condensed" id="tbl-alerts">
                <thead>
                    <tr>
                        <th>{{ lang._('Name') }}</th>
                        <th>{{ lang._('Threshold') }}</th>
                        <th>{{ lang._('Level') }}</th>
                        <th>{{ lang._('Matchers') }}</th>
                        <th>{{ lang._('Last Triggered') }}</th>
                        <th style="text-align:right;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody></tbody>
            </table>
        </div>
    </div>

    <!-- Tab 2: Ignore Rules -->
    <div id="tab-ignores" class="tab-pane">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
            <h4 style="margin:0;">{{ lang._('Ignore & Discard Rules') }}</h4>
            <button type="button" id="btn-add-ignore" class="btn btn-primary btn-sm"><i class="fa fa-plus"></i> {{ lang._('Add Ignore Rule') }}</button>
        </div>
        <div class="table-responsive">
            <table class="table table-striped table-condensed" id="tbl-ignores">
                <thead>
                    <tr>
                        <th>{{ lang._('Mode') }}</th>
                        <th>{{ lang._('Level') }}</th>
                        <th>{{ lang._('Matchers') }}</th>
                        <th style="text-align:right;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody></tbody>
            </table>
        </div>
    </div>

    <!-- Tab 3: Severity Rewrites -->
    <div id="tab-rewrites" class="tab-pane">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
            <h4 style="margin:0;">{{ lang._('Severity Rewrite Rules (First Match Wins)') }}</h4>
            <button type="button" id="btn-add-rewrite" class="btn btn-primary btn-sm"><i class="fa fa-plus"></i> {{ lang._('Add Rewrite Rule') }}</button>
        </div>
        <div class="table-responsive">
            <table class="table table-striped table-condensed" id="tbl-rewrites">
                <thead>
                    <tr>
                        <th style="width:40px;">#</th>
                        <th>{{ lang._('Source Level') }}</th>
                        <th>{{ lang._('Matchers') }}</th>
                        <th>{{ lang._('New Severity') }}</th>
                        <th style="text-align:right;">{{ lang._('Actions') }}</th>
                    </tr>
                </thead>
                <tbody></tbody>
            </table>
        </div>
    </div>

    <!-- Tab 4: Digest Escalation -->
    <div id="tab-digest" class="tab-pane">
        <h4>{{ lang._('Alert Digest & Escalating Windows') }}</h4>
        <div class="row">
            <div class="col-md-6">
                <div class="checkbox">
                    <label><input type="checkbox" id="dig-enabled"> <b>{{ lang._('Enable Digest Batching') }}</b></label>
                </div>
                <div class="form-group">
                    <label>{{ lang._('Initial Window') }}</label>
                    <input type="text" id="dig-initial" class="form-control input-sm" placeholder="5m">
                </div>
                <div class="form-group">
                    <label>{{ lang._('Multiplier (>= 1.5)') }}</label>
                    <input type="number" step="0.5" min="1.5" id="dig-multiplier" class="form-control input-sm">
                </div>
                <div class="form-group">
                    <label>{{ lang._('Maximum Window') }}</label>
                    <input type="text" id="dig-max" class="form-control input-sm" placeholder="2h">
                </div>
                <div class="form-group">
                    <label>{{ lang._('Reset Cooldown') }}</label>
                    <input type="text" id="dig-cooldown" class="form-control input-sm" placeholder="10m">
                </div>
                <button type="button" id="btn-save-digest" class="btn btn-primary btn-sm">{{ lang._('Save Digest Settings') }}</button>
            </div>
            <div class="col-md-6">
                <table class="table table-condensed table-striped">
                    <thead><tr><th colspan="2">{{ lang._('Live Digest State') }}</th></tr></thead>
                    <tbody>
                        <tr><td>{{ lang._('Queued Rules') }}</td><td id="dig-queued">0</td></tr>
                        <tr><td>{{ lang._('Current Escalation Window') }}</td><td id="dig-window">--</td></tr>
                        <tr><td>{{ lang._('Next Flush') }}</td><td id="dig-next-flush">--</td></tr>
                        <tr><td>{{ lang._('Last Digest Sent') }}</td><td id="dig-last-sent">--</td></tr>
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <!-- Tab 5: Monaco YAML Editor -->
    <div id="tab-yaml" class="tab-pane">
        <div style="margin: 0 0 10px 0; display: flex; align-items: center; justify-content: space-between;">
            <h4 style="margin:0;">{{ lang._('Rules YAML (100% compatible with mietzen/logyard config.yaml)') }}</h4>
            <div style="display:flex; align-items:center; gap: 8px;">
                <div class="btn-group btn-group-xs">
                    <button type="button" class="btn btn-default" id="btn-yaml-wrap" title="{{ lang._('Word Wrap') }}"><i class="fa fa-align-left"></i></button>
                    <button type="button" class="btn btn-default" id="btn-yaml-minimap" title="{{ lang._('Minimap') }}"><i class="fa fa-map-o"></i></button>
                    <button type="button" class="btn btn-default" id="btn-yaml-font-dec" title="{{ lang._('Smaller Font') }}"><i class="fa fa-minus"></i></button>
                    <button type="button" class="btn btn-default" id="btn-yaml-font-inc" title="{{ lang._('Larger Font') }}"><i class="fa fa-plus"></i></button>
                    <button type="button" class="btn btn-default" id="btn-yaml-theme" title="{{ lang._('Toggle Theme') }}"><i class="fa fa-sun-o" id="ly-theme-icon"></i></button>
                </div>
                <button type="button" id="btn-save-yaml" class="btn btn-primary btn-xs" style="padding: 4px 12px;"><b>{{ lang._('Validate & Save') }}</b></button>
            </div>
        </div>
        <div id="ly-yaml-editor" style="height: 480px; border: 1px solid #1d2733; border-radius: 4px; overflow: hidden;"></div>
        <span class="help-block" style="margin-top: 8px;">
            {{ lang._('Supports pasting full mietzen/logyard config.yaml files (extracts alerts, ignore, severity_rewrite, and digest). Validated before saving to config.xml.') }}
        </span>
    </div>
</div>

<!-- Alert Rule Modal -->
<div class="modal fade ly-modal" id="modal-alert" tabindex="-1" role="dialog">
    <div class="modal-dialog"><div class="modal-content">
        <div class="modal-header"><button type="button" class="close" data-dismiss="modal">&times;</button><h4 class="modal-title" style="margin-top:0;">{{ lang._('Alert Rule') }}</h4></div>
        <div class="modal-body">
            <div class="form-group"><label>{{ lang._('Rule Name') }}</label><input type="text" id="al-name" class="form-control input-sm"></div>
            <div class="row">
                <div class="col-sm-4"><div class="form-group"><label>{{ lang._('Count') }}</label><input type="number" min="1" id="al-count" class="form-control input-sm"></div></div>
                <div class="col-sm-4"><div class="form-group"><label>{{ lang._('Window (min)') }}</label><input type="number" min="1" id="al-window" class="form-control input-sm"></div></div>
                <div class="col-sm-4"><div class="form-group"><label>{{ lang._('Level') }}</label>
                    <select id="al-level" class="form-control input-sm"><option value="emerg">emerg</option><option value="alert">alert</option><option value="crit">crit</option><option value="err">err</option><option value="warning">warning</option><option value="notice">notice</option><option value="info">info</option><option value="debug">debug</option></select>
                </div></div>
            </div>
            <div class="checkbox"><label><input type="checkbox" id="al-above"> {{ lang._('Match this level AND all more severe levels (above: true)') }}</label></div>
            <div class="row">
                <div class="col-sm-6"><div class="form-group"><label>{{ lang._('Host (exact, optional)') }}</label><input type="text" id="al-host" class="form-control input-sm"></div></div>
                <div class="col-sm-6"><div class="form-group"><label>{{ lang._('Facility (exact, optional)') }}</label><input type="text" id="al-facility" class="form-control input-sm"></div></div>
            </div>
            <div class="form-group"><label>{{ lang._('Tag (regex, optional)') }}</label><input type="text" id="al-tag" class="form-control input-sm"></div>
            <div class="form-group"><label>{{ lang._('Message (regex, optional)') }}</label><input type="text" id="al-message" class="form-control input-sm"></div>
        </div>
        <div class="modal-footer"><button class="btn btn-default" data-dismiss="modal">{{ lang._('Cancel') }}</button><button class="btn btn-primary" id="al-save-btn">{{ lang._('Save') }}</button></div>
    </div></div>
</div>

<!-- Ignore Rule Modal -->
<div class="modal fade ly-modal" id="modal-ignore" tabindex="-1" role="dialog">
    <div class="modal-dialog"><div class="modal-content">
        <div class="modal-header"><button type="button" class="close" data-dismiss="modal">&times;</button><h4 class="modal-title" style="margin-top:0;">{{ lang._('Ignore / Discard Rule') }}</h4></div>
        <div class="modal-body">
            <div class="checkbox"><label><input type="checkbox" id="ir-discard"> <b>{{ lang._('Discard at ingest (drop before SQLite DB)') }}</b></label></div>
            <div class="row">
                <div class="col-sm-4"><div class="form-group"><label>{{ lang._('Host (exact)') }}</label><input type="text" id="ir-host" class="form-control input-sm"></div></div>
                <div class="col-sm-4"><div class="form-group"><label>{{ lang._('Facility (exact)') }}</label><input type="text" id="ir-facility" class="form-control input-sm"></div></div>
                <div class="col-sm-4"><div class="form-group"><label>{{ lang._('Level (exact)') }}</label>
                    <select id="ir-level" class="form-control input-sm"><option value="">Any</option><option value="emerg">emerg</option><option value="alert">alert</option><option value="crit">crit</option><option value="err">err</option><option value="warning">warning</option><option value="notice">notice</option><option value="info">info</option><option value="debug">debug</option></select>
                </div></div>
            </div>
            <div class="form-group"><label>{{ lang._('Tag (regex)') }}</label><input type="text" id="ir-tag" class="form-control input-sm"></div>
            <div class="form-group"><label>{{ lang._('Message (regex)') }}</label><input type="text" id="ir-message" class="form-control input-sm"></div>
        </div>
        <div class="modal-footer"><button class="btn btn-default" data-dismiss="modal">{{ lang._('Cancel') }}</button><button class="btn btn-primary" id="ir-save-btn">{{ lang._('Save') }}</button></div>
    </div></div>
</div>

<!-- Rewrite Rule Modal -->
<div class="modal fade ly-modal" id="modal-rewrite" tabindex="-1" role="dialog">
    <div class="modal-dialog"><div class="modal-content">
        <div class="modal-header"><button type="button" class="close" data-dismiss="modal">&times;</button><h4 class="modal-title" style="margin-top:0;">{{ lang._('Severity Rewrite Rule') }}</h4></div>
        <div class="modal-body">
            <div class="row">
                <div class="col-sm-6"><div class="form-group"><label>{{ lang._('Source Level (optional)') }}</label>
                    <select id="rw-level" class="form-control input-sm"><option value="">Any</option><option value="emerg">emerg</option><option value="alert">alert</option><option value="crit">crit</option><option value="err">err</option><option value="warning">warning</option><option value="notice">notice</option><option value="info">info</option><option value="debug">debug</option></select>
                </div></div>
                <div class="col-sm-6"><div class="form-group"><label>{{ lang._('New Severity') }}</label>
                    <select id="rw-new-sev" class="form-control input-sm"><option value="emerg">emerg</option><option value="alert">alert</option><option value="crit">crit</option><option value="err">err</option><option value="warning">warning</option><option value="notice">notice</option><option value="info">info</option><option value="debug">debug</option></select>
                </div></div>
            </div>
            <div class="row">
                <div class="col-sm-6"><div class="form-group"><label>{{ lang._('Host (exact)') }}</label><input type="text" id="rw-host" class="form-control input-sm"></div></div>
                <div class="col-sm-6"><div class="form-group"><label>{{ lang._('Facility (exact)') }}</label><input type="text" id="rw-facility" class="form-control input-sm"></div></div>
            </div>
            <div class="form-group"><label>{{ lang._('Tag (regex)') }}</label><input type="text" id="rw-tag" class="form-control input-sm"></div>
            <div class="form-group"><label>{{ lang._('Message (regex)') }}</label><input type="text" id="rw-message" class="form-control input-sm"></div>
        </div>
        <div class="modal-footer"><button class="btn btn-default" data-dismiss="modal">{{ lang._('Cancel') }}</button><button class="btn btn-primary" id="rw-save-btn">{{ lang._('Save') }}</button></div>
    </div></div>
</div>
