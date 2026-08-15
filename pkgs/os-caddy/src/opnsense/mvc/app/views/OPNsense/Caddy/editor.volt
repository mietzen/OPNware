{#
 # OPNware os-caddy — Caddyfile Editor
 #
 # The user-owned Caddy config at /usr/local/etc/caddy is a flat tree:
 # Caddyfile plus conf.d/*.caddy (the import glob is non-recursive). ACME
 # storage, autosave, certs and keys are invisible. Saving validates the
 # staged tree with `caddy validate`, applies it atomically and reloads
 # Caddy gracefully; a reload failure rolls back to the previous config.
 #
 # The editor is Monaco (vendored, no CDN) with Caddyfile syntax highlighting
 # from the vendored TextMate grammar (caddyserver/vscode-caddyfile). The
 # hidden <textarea id="editor-content"> stays in the DOM as the transport for
 # the existing save cycle: Monaco writes every model change back into it, so
 # the /api/caddy/editor/save endpoint is untouched.
 #}

<style>
    .opnware-editor-tabs { margin-bottom: 15px; }
    .editor-tree-root, .editor-tree-directory, .editor-tree-file-row { padding: 5px 0; }
    .editor-tree-children { margin: 3px 0 0 14px; border-left: 1px solid #d8dee4; padding-left: 10px; }
    .editor-tree-toggle { width: 22px; padding: 0; text-decoration: none; }
    .editor-tree-label { font-weight: 600; }
    .editor-tree-file { display: inline-block; min-width: 105px; padding: 4px 6px; }
    .editor-tree-file-row .btn { vertical-align: middle; }
    .opnware-editor-shell { margin: 0; }
    .opnware-editor-pane { padding: 15px; }
    .opnware-editor-actions { padding: 0 15px 15px; }
    @media (max-width: 767px) {
        .editor-tree-file { min-width: 85px; }
        .editor-tree-file-row .btn { margin-top: 4px; }
    }
</style>

<script src="/ui/js/vendor/monaco/vs/loader.js"></script>
<script>
    // Monaco's AMD loader (vs/loader.js) resolves module ids through these
    // paths. Everything is vendored under /opnsense/www/js/vendor/ (served as
    // /ui/js/vendor/...); see docs/design/shared-editor-vendor.md.
    require.config({
        paths: {
            vs: '/ui/js/vendor/monaco/vs',
            'vscode-textmate': '/ui/js/vendor/textmate/vscode-textmate/main',
            'vscode-oniguruma': '/ui/js/vendor/textmate/vscode-oniguruma/release/main',
            'monaco-editor-textmate': '/ui/js/vendor/textmate/monaco-editor-textmate'
        }
    });

    $(document).ready(function() {
        let currentFile = null;
        let editor = null;

        // --- Monaco + TextMate grammar wiring -------------------------------

        require(['vs/editor/editor.main'], function(monaco) {
            window.opnwareMonaco = monaco;
            monaco.languages.register({ id: 'caddyfile' });

            editor = monaco.editor.create(document.getElementById('editor-container'), {
                value: document.getElementById('editor-content').value,
                language: 'caddyfile',
                theme: preferredEditorTheme(),
                automaticLayout: true,
                minimap: { enabled: false },
                fontSize: 13,
                tabSize: 2,
                wordWrap: 'on',
                scrollBeyondLastLine: false,
                lineNumbersMinChars: 3
            });

            syncEditorTheme();

            // Keep the hidden textarea (the save transport) in sync with the
            // Monaco model so the existing save flow works unchanged.
            editor.onDidChangeModelContent(function() {
                document.getElementById('editor-content').value = editor.getValue();
            });

            require(['vscode-textmate', 'vscode-oniguruma', 'monaco-editor-textmate'],
                function(tm, onig, bridge) {
                    wireCaddyfileGrammar(monaco, tm, onig, bridge);
                }
            );
        });

        function preferredEditorTheme() {
            const saved = window.localStorage.getItem('opnware-editor-theme');
            if (saved === 'vs' || saved === 'vs-dark') {
                return saved;
            }
            return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
                ? 'vs-dark' : 'vs';
        }

        function syncEditorTheme() {
            if (!editor || !window.opnwareMonaco) {
                return;
            }
            window.opnwareMonaco.editor.setTheme(preferredEditorTheme());
            $('#editor-theme').val(preferredEditorTheme());
        }

        $('#editor-theme').change(function() {
            window.localStorage.setItem('opnware-editor-theme', $(this).val());
            syncEditorTheme();
        });

        if (window.matchMedia) {
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function() {
                if (!window.localStorage.getItem('opnware-editor-theme')) {
                    syncEditorTheme();
                }
            });
        }

        // Load the vendored oniguruma wasm and register the Caddyfile TextMate
        // grammar as Monaco token provider. The grammar JSON is passed to the
        // vscode-textmate Registry as a raw IRawGrammar object.
        function wireCaddyfileGrammar(monaco, tm, onig, bridge) {
            fetch('/ui/js/vendor/textmate/vscode-oniguruma/release/onig.wasm')
                .then(function(r) { return r.arrayBuffer(); })
                .then(function(wasmData) { return onig.loadWASM({ data: wasmData }); })
                .then(function() {
                    return fetch('/ui/js/vendor/caddyfile.tmLanguage.json').then(function(r) { return r.json(); });
                })
                .then(function(grammarJson) {
                    var registry = new tm.Registry({
                        onigLib: Promise.resolve({
                            createOnigScanner: onig.createOnigScanner,
                            createOnigString: onig.createOnigString
                        }),
                        loadGrammar: function(scopeName) {
                            return Promise.resolve(scopeName === 'source.Caddyfile' ? grammarJson : null);
                        }
                    });
                    return bridge.wireTmGrammars(
                        monaco, registry, new Map([['caddyfile', 'source.Caddyfile']])
                    );
                })
                .then(function() {
                    var model = editor && editor.getModel();
                    if (model && typeof model.forceTokenization === 'function') {
                        model.forceTokenization(model.getLineCount());
                    }
                })
                .catch(function(err) {
                    console.error('Caddyfile grammar wiring failed:', err);
                });
        }

        // Set the current document in both the transport textarea and Monaco.
        function setEditorValue(content) {
            $("#editor-content").val(content);
            if (editor) {
                editor.setValue(content || '');
            }
        }

        // --- existing file-tree logic ---------------------------------------

        function loadTree() {
            $.getJSON("/api/caddy/editor/list", function(data) {
                if (data.status !== "ok") {
                    showError(data.message);
                    return;
                }
                const $list = $("#editor-files");
                $list.empty();
                const $root = $('<li class="editor-tree-root">').append(
                    $('<a href="#" class="editor-tree-file">').text('Caddyfile').click(function(e) {
                        e.preventDefault();
                        loadFile('Caddyfile');
                    })
                );
                $list.append($root);
                $list.append(renderTreeNode(data.tree));
            });
        }

        function renderTreeNode(node) {
            const $item = $('<li class="editor-tree-directory">');
            const $toggle = $('<button type="button" class="btn btn-link btn-xs editor-tree-toggle" aria-expanded="true">')
                .text('▾');
            const $label = $('<span class="editor-tree-label">').text(node.name);
            const $children = $('<ul class="nav nav-pills nav-stacked editor-tree-children">');
            (node.children || []).forEach(function(child) {
                if (child.type === 'directory') {
                    const $child = renderTreeNode(child);
                    $children.append($child);
                } else {
                    const $file = $('<li class="editor-tree-file-row">');
                    const $link = $('<a href="#" class="editor-tree-file">').text(child.name).click(function(e) {
                        e.preventDefault();
                        loadFile(child.path);
                    });
                    const $copy = $('<button type="button" class="btn btn-xs btn-default __ml">').text('{{ lang._("Copy") }}')
                        .click(function(e) { e.stopPropagation(); copyOrMoveFile(child.path, false); });
                    const $move = $('<button type="button" class="btn btn-xs btn-default __ml">').text('{{ lang._("Move") }}')
                        .click(function(e) { e.stopPropagation(); copyOrMoveFile(child.path, true); });
                    const $del = $('<button type="button" class="btn btn-xs btn-danger __ml">').text('{{ lang._("Delete") }}')
                        .click(function(e) { e.stopPropagation(); deleteFile(child.path); });
                    $file.append($link).append($copy).append($move).append($del);
                    $children.append($file);
                }
            });
            $toggle.click(function() {
                const expanded = $toggle.attr('aria-expanded') === 'true';
                $toggle.attr('aria-expanded', !expanded).text(expanded ? '▸' : '▾');
                $children.toggle(!expanded);
            });
            $item.append($toggle).append($label).append($children);
            return $item;
        }

        function copyOrMoveFile(path, move) {
            const name = window.prompt(
                move ? "{{ lang._('Move to relative path, e.g. conf.d/archive/site.caddy') }}" : "{{ lang._('Copy to relative path, e.g. conf.d/archive/site.caddy') }}",
                ''
            );
            if (!name) {
                return;
            }
            $.post('/api/caddy/editor/' + (move ? 'move' : 'copy'), {path: path, target: name}, function(data) {
                if (data.status !== 'ok') {
                    showError(data.message);
                    return;
                }
                loadTree();
            });
        }

        function loadFile(path) {
            $.getJSON("/api/caddy/editor/get", {path: path}, function(data) {
                if (data.status !== "ok") {
                    showError(data.message);
                    return;
                }
                currentFile = path;
                $("#editor-name").text(data.name);
                $("#editor-path").text(data.path);
                setEditorValue(data.content || '');
            });
        }

        function deleteFile(path) {
            if (!confirm("{{ lang._('Delete this file?') }}")) {
                return;
            }
            $.post("/api/caddy/editor/delete", {path: path}, function(data) {
                if (data.status !== "ok") {
                    showError(data.message);
                    return;
                }
                if (currentFile === path) {
                    currentFile = null;
                    setEditorValue('');
                    $("#editor-name").text('');
                    $("#editor-path").text('');
                }
                loadTree();
            });
        }

        $("#save-editor").click(function() {
            if (!currentFile) {
                return;
            }
            $("#editor-result").hide();
            $.post("/api/caddy/editor/save", {
                path: currentFile,
                content: $("#editor-content").val()
            }, function(data) {
                if (data.status === "ok") {
                    showSuccess(data.message || "{{ lang._('Saved') }}");
                } else {
                    showError(data.message || JSON.stringify(data));
                }
                updateStatus();
            });
        });

        $("#add-editor").click(function() {
            const name = $("#new-file-name").val().trim();
            if (!name) {
                return;
            }
            $("#editor-result").hide();
            $.post("/api/caddy/editor/add", {name: name}, function(data) {
                if (data.status !== "ok") {
                    showError(data.message);
                    return;
                }
                $("#new-file-name").val('');
                loadTree();
            });
        });

        function showError(message) {
            const $box = $("#editor-result");
            $box.removeClass("alert-success").addClass("alert-danger");
            $box.text(message || "{{ lang._('Error') }}");
            $box.show();
        }

        function showSuccess(message) {
            const $box = $("#editor-result");
            $box.removeClass("alert-danger").addClass("alert-success");
            $box.text(message);
            $box.show();
        }

        function updateStatus() {
            $.getJSON("/api/caddy/editor/status", function(data) {
                const $status = $("#editor-status");
                if (!$status.length) {
                    return;
                }
                $status.find("#status-last-save").text(
                    data.last_save ? new Date(data.last_save * 1000).toLocaleString() : "-"
                );
                $status.find("#status-result").text(
                    data.result === "ok" ? "{{ lang._('OK') }}"
                    : (data.result === "failure" ? "{{ lang._('FAILED') }}" : "-")
                );
                $status.find("#status-message").text(data.message || "-");
                $status.find("#status-rollback").text(
                    data.rollback === true ? "{{ lang._('yes') }}" : "{{ lang._('no') }}"
                );
            });
        }

        loadTree();
        updateStatus();
    });
</script>

<script>
    // --- Environment grid -----------------------------------------------
    // Independent of Monaco: the envfile grid works even when the editor
    // JavaScript fails to load. Rows are name · value · secret checkbox.
    // Secret rows are masked ('********') until revealed per-row; the real
    // value of one row is fetched from the API on demand. The plugin-owned
    // CADDY_LOG_LEVEL row is shown read-only and is never submitted.
    $(document).ready(function() {
        const ENV_MASK = '********';
        let envRows = [];

        function envShowError(message) {
            const $box = $("#env-result");
            $box.removeClass("alert-success").addClass("alert-danger");
            $box.text(message || "{{ lang._('Error') }}");
            $box.show();
        }

        function envShowSuccess(message) {
            const $box = $("#env-result");
            $box.removeClass("alert-danger").addClass("alert-success");
            $box.text(message);
            $box.show();
        }

        function envClearRowError(index) {
            if (index < 0 || index >= envRows.length) {
                return;
            }
            envRows[index].error = '';
            $("#env-table tbody tr[data-error-index='" + index + "']").remove();
        }

        function envReveal(index) {
            const row = envRows[index];
            $.post("/api/caddy/env/reveal", {name: row.name}, function(data) {
                if (data.status !== "ok") {
                    envShowError(data.message);
                    return;
                }
                row.value = data.value;
                row.revealed = true;
                envRender();
            });
        }

        function envHide(index) {
            const row = envRows[index];
            row.value = ENV_MASK;
            row.revealed = false;
            envRender();
        }

        function envRender() {
            const $tbody = $("#env-table tbody");
            $tbody.empty();
            envRows.forEach(function(row, index) {
                const $tr = $('<tr>').attr('data-index', index);

                // Name
                const $name = $('<input type="text" class="form-control input-sm" spellcheck="false">')
                    .val(row.name)
                    .attr('placeholder', 'VAR_NAME');
                if (row.readonly) {
                    $name.prop('disabled', true);
                } else {
                    $name.on('input', function() {
                        row.name = $(this).val();
                        envClearRowError(index);
                    });
                }
                $tr.append($('<td>').append($name));

                // Value
                const $value = $('<input type="text" class="form-control input-sm" spellcheck="false">')
                    .val(row.value);
                if (row.readonly) {
                    $value.prop('disabled', true);
                } else {
                    $value.on('input', function() {
                        row.value = $(this).val();
                        envClearRowError(index);
                    });
                }
                $tr.append($('<td>').append($value));

                // Secret checkbox (checked by default; disabled for the plugin row)
                const $secret = $('<input type="checkbox">')
                    .prop('checked', row.secret)
                    .prop('disabled', row.readonly);
                $secret.change(function() {
                    row.secret = $(this).is(':checked');
                    if (!row.secret && row.value === ENV_MASK) {
                        // Non-secret rows must be visible — fetch the real value.
                        envReveal(index);
                    } else if (row.secret && row.revealed) {
                        envHide(index);
                    }
                });
                $tr.append($('<td>').append($secret));

                // Per-row reveal toggle for secret rows
                const $tdReveal = $('<td>');
                if (row.secret && !row.readonly) {
                    const $toggle = $('<button type="button" class="btn btn-xs btn-default" title="Show / hide value">')
                        .html(row.revealed ? '<i class="fa fa-eye-slash"></i>' : '<i class="fa fa-eye"></i>')
                        .click(function() {
                            if (row.revealed) {
                                envHide(index);
                            } else if (row.value === ENV_MASK) {
                                envReveal(index);
                            } else {
                                row.revealed = true;
                                envRender();
                            }
                        });
                    $tdReveal.append($toggle);
                }
                $tr.append($tdReveal);

                // Delete
                const $tdDelete = $('<td>');
                if (!row.readonly) {
                    const $del = $('<button type="button" class="btn btn-xs btn-danger">')
                        .text("{{ lang._('Delete') }}")
                        .click(function() {
                            envRows.splice(index, 1);
                            envRender();
                        });
                    $tdDelete.append($del);
                }
                $tr.append($tdDelete);

                $tbody.append($tr);
                if (row.error) {
                    $tbody.append(
                        $('<tr class="env-error-row" data-error-index="' + index + '">')
                            .append($('<td colspan="5" class="text-danger">').text(row.error))
                    );
                }
            });
        }

        function envSetErrors(errors) {
            errors.forEach(function(e) {
                const i = parseInt(e.index, 10);
                if (i >= 0 && i < envRows.length) {
                    envRows[i].error = e.error || "{{ lang._('Invalid row') }}";
                }
            });
            envRender();
        }

        function envSave() {
            $("#env-result").hide();
            const payload = [];
            const payloadMap = [];
            envRows.forEach(function(row, i) {
                if (row.readonly || String(row.name).trim() === '') {
                    return;
                }
                payloadMap.push(i);
                payload.push({name: row.name, value: row.value, secret: row.secret});
            });
            $.post("/api/caddy/env/save", {rows: payload}, function(data) {
                if (data.status !== "ok") {
                    envShowError(data.message || "{{ lang._('Save failed') }}");
                    if (data.errors && data.errors.length) {
                        envSetErrors(data.errors);
                    }
                    return;
                }
                // Mirror the file: drop empty rows, keep the last occurrence
                // of duplicated names (later duplicates win).
                const seen = {};
                const dedup = [];
                envRows.forEach(function(row) {
                    if (row.readonly) {
                        dedup.push(row);
                        return;
                    }
                    if (String(row.name).trim() === '') {
                        return;
                    }
                    if (seen.hasOwnProperty(row.name)) {
                        dedup[seen[row.name]] = row;
                    } else {
                        seen[row.name] = dedup.length;
                        dedup.push(row);
                    }
                });
                envRows = dedup;
                envRender();
                envShowSuccess(data.message || "{{ lang._('Saved') }}");
            });
        }

        function envLoad() {
            $.getJSON("/api/caddy/env/get", function(data) {
                if (data.status !== "ok") {
                    envShowError(data.message);
                    return;
                }
                envRows = (data.rows || []).map(function(r) {
                    return {
                        name: r.name || '',
                        value: r.value || '',
                        secret: !!r.secret,
                        readonly: !!r.readonly,
                        revealed: false,
                        error: ''
                    };
                });
                envRender();
            });
        }

        $("#env-add-row").click(function() {
            envRows.push({name: '', value: '', secret: true, readonly: false, revealed: false, error: ''});
            envRender();
        });

        $("#env-save").click(envSave);

        envLoad();
    });
</script>

<div id="editor-result" class="alert" style="display:none;"></div>

<ul class="nav nav-tabs opnware-editor-tabs" role="tablist">
    <li class="active"><a href="#editor-files-tab" data-toggle="tab">{{ lang._('Files') }}</a></li>
    <li><a href="#editor-environment-tab" data-toggle="tab">{{ lang._('Environment') }}</a></li>
</ul>

<div class="tab-content">
<div id="editor-files-tab" class="tab-pane active">
<div class="row">
    <div class="col-md-3">
        <div class="content-box __mb" style="padding-bottom: 1.5em;">
            <div class="content-box-main">
                <h2>{{ lang._('Files') }}</h2>
                <ul id="editor-files" class="nav nav-pills nav-stacked"></ul>
            </div>
            <div class="content-box-main" style="padding-top: 0;">
                <div class="form-group">
                    <input id="new-file-name" type="text" class="form-control input-sm" placeholder="site.caddy">
                </div>
                <button id="add-editor" type="button" class="btn btn-primary btn-sm">{{ lang._('Add') }}</button>
                <span class="help-block">{{ lang._('Add and delete are limited to .caddy files inside conf.d. The Caddyfile itself cannot be deleted.') }}</span>
            </div>
        </div>
    </div>
    <div class="col-md-9">
        <div class="content-box __mb" style="padding-bottom: 1.5em;">
            <div class="content-box-main">
                <div class="row">
                    <div class="col-md-8"><h2 id="editor-name">{{ lang._('Caddyfile') }}</h2></div>
                    <div class="col-md-4 text-right __mt">
                        <label class="text-muted" for="editor-theme">{{ lang._('Theme') }}</label>
                        <select id="editor-theme" class="form-control input-sm" style="display:inline-block; width:auto;">
                            <option value="vs">{{ lang._('Light') }}</option>
                            <option value="vs-dark">{{ lang._('Dark') }}</option>
                        </select>
                    </div>
                </div>
                <p><small class="text-muted"><code id="editor-path"></code></small></p>
                <div id="editor-container" style="height: 450px; border: 1px solid #1d2733; border-radius: 4px; overflow: hidden;"></div>
                {# Hidden transport for the existing save cycle — the Monaco model mirrors its value. #}
                <textarea id="editor-content" class="form-control" rows="20" spellcheck="false"
                          style="font-family: monospace; display: none;"></textarea>
            </div>
            <div class="col-md-12 __mt">
                <hr/>
                <button id="save-editor" type="button" class="btn btn-primary"><b>{{ lang._('Save') }}</b></button>
                <span id="editor-status" class="text-muted __ml">
                    {{ lang._('Last save') }}: <span id="status-last-save">-</span>
                    · <span id="status-result">-</span>
                    · <span id="status-rollback">-</span>
                    · <span id="status-message">-</span>
                </span>
            </div>
            <div class="content-box-main" style="padding-top: 5px;">
                <span class="help-block">{{ lang._('Saving validates the whole Caddy file tree first; invalid configuration is rejected without writing anything.') }}</span>
            </div>
        </div>
    </div>
</div>
</div>

<div id="editor-environment-tab" class="tab-pane">
<div id="env-panel" class="content-box __mb" style="padding-bottom: 1.5em;">
    <div class="content-box-main">
        <h2>{{ lang._('Environment') }}</h2>
        <p class="help-block">
            {{ lang._('Environment variables are passed to the Caddy process through the envfile (--envfile). Secret rows are masked by default; use the reveal button to inspect a value. The plugin-managed CADDY_LOG_LEVEL row cannot be edited. The envfile is separate from the file tree above and is never shown there.') }}
        </p>
        <table class="table table-striped table-condensed" id="env-table">
            <thead>
                <tr>
                    <th>{{ lang._('Name') }}</th>
                    <th>{{ lang._('Value') }}</th>
                    <th>{{ lang._('Secret') }}</th>
                    <th></th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td colspan="5" class="text-muted">{{ lang._('Loading…') }}</td>
                </tr>
            </tbody>
        </table>
    </div>
    <div class="col-md-12 __mt">
        <hr/>
        <button id="env-add-row" type="button" class="btn btn-primary"><b>{{ lang._('Add row') }}</b></button>
        <button id="env-save" type="button" class="btn btn-primary __ml"><b>{{ lang._('Save env') }}</b></button>
    </div>
    <div class="content-box-main" style="padding-top: 5px; padding-bottom: 15px;">
        <div id="env-result" class="alert" style="display:none;"></div>
    </div>
</div>
</div>
</div>
