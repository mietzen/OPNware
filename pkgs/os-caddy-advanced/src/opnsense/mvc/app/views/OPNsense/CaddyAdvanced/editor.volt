{#
 # OPNware os-caddy-advanced — Caddyfile Editor
 #
 # The user-owned Caddy config at /usr/local/etc/caddy is flat: Caddyfile
 # plus conf.d/*.caddy (the seed Caddyfile is `import conf.d/*.caddy`, a
 # non-recursive glob). ACME storage, autosave, certs and keys are invisible.
 # Saving validates the staged tree with `caddy validate`, applies it
 # atomically and reloads Caddy gracefully; a reload failure rolls back to
 # the previous config.
 #
 # The editor is Monaco (vendored, no CDN) with Caddyfile syntax highlighting
 # from a hand-written Monarch grammar (pkgs/monaco-editor/src/caddyfile.js,
 # shipped as /ui/js/vendor/caddyfile.js). The grammar only emits tokens that
 # exist in the stock vs/vs-dark themes, so no theme extension is needed. The
 # hidden <textarea id="editor-content"> stays in the DOM as the transport for
 # the existing save cycle: Monaco writes every model change back into it, so
 # the /api/caddyadvanced/editor/save endpoint is untouched.
 #
 # The file tree is jstree (vendored, no CDN): right-click context menu
 # (new file, rename, copy, move, delete) and drag-and-drop moves. jstree
 # must load BEFORE monaco's vs/loader.js — the AMD loader's global define
 # would otherwise swallow jstree into AMD mode and $.fn.jstree never gets
 # set.
 #}

<link rel="stylesheet" href="/ui/js/vendor/jstree/themes/default/style.min.css">

<style>
    .opnware-editor-tabs { margin-bottom: 0; }
    .opnware-tab-pane { padding: 15px 15px 15px; }
    .opnware-tab-pane h2 { margin-top: 0; }
    .content-box.opnware-editor-pane { padding: 15px; }
    /* jstree appends its context menu to <body> with z-index auto; the Monaco
       editor creates its own stacking context, so the menu would render
       behind it. Lift it above the editor. */
    .vakata-context { z-index: 10000 !important; }
    /* jstree context menu theming: match the OPNsense panel look instead of
       the default boxy desktop-menu styling. Theme-aware colors come from
       the core :root CSS variables. */
    .vakata-context,
    .vakata-context ul {
        background: var(--bs-body-bg, #fff);
        border: 1px solid var(--bs-border-color, #ccc);
        border-radius: 4px;
        box-shadow: 0 2px 8px rgba(0, 0, 0, .15);
        padding: 4px 0;
    }
    .vakata-context li > a {
        padding: 4px 14px;
        font-size: 12px;
        line-height: 1.4;
        color: var(--bs-body-color, #333);
        border: 0;
        box-shadow: none;
    }
    /* jstree emits an empty icon placeholder (<i>) and a 1px vertical
       separator span before every menu label; the vendored default theme
       sizes both at 2.4em. Hide them so items are compact and the labels
       are flush against the left edge. */
    .vakata-context li > a > i,
    .vakata-context li > a .vakata-contextmenu-sep { display: none; }
    .vakata-context li > a:hover,
    .vakata-context li > a.vakata-context-hover {
        background: var(--bs-primary, #3f7e9d);
        color: #fff;
        box-shadow: none;
        text-shadow: none;
    }
    .vakata-context .vakata-context-separator {
        border: 0;
        border-top: 1px solid var(--bs-border-color, #e0e0e0);
        height: 0;
        margin: 3px 0;
    }
    .opnware-editor-actions { padding: 0 15px 15px; }
    .opnware-editor-split { display: flex; align-items: stretch; }
    .opnware-editor-tree {
        flex: 0 0 280px;
        max-width: 280px;
        padding-right: 15px;
        margin-right: 15px;
        border-right: 1px solid #E5E5E5;
    }
    .opnware-editor-main { flex: 1 1 auto; min-width: 0; }
    #editor-tree { min-height: 120px; }
    #editor-tree .jstree-anchor { max-width: 100%; }
    #editor-tree .jstree-anchor .jstree-icon { margin-right: 4px; }
    @media (max-width: 767px) {
        .opnware-editor-split { flex-direction: column; }
        .opnware-editor-tree {
            flex: none;
            max-width: 100%;
            padding-right: 0;
            margin-right: 0;
            border-right: 0;
            border-bottom: 1px solid #E5E5E5;
            margin-bottom: 15px;
            padding-bottom: 15px;
        }
    }
</style>

<script src="/ui/js/vendor/jstree/jstree.min.js"></script>
<script src="/ui/js/vendor/monaco/vs/loader.js"></script>
<script>
    // Monaco's AMD loader (vs/loader.js) resolves module ids through these
    // paths. Everything is vendored under /opnsense/www/js/vendor/ (served as
    // /ui/js/vendor/...); see docs/design/shared-editor-vendor.md.
    //
    // CSP extension for this page: worker-src 'self' blob: + font-src
    // 'self' data: (per-controller content_security_policy merge in
    // ControllerBase). See docs/design/shared-editor-vendor.md.
    require.config({
        paths: {
            vs: '/ui/js/vendor/monaco/vs',
            caddyfile: '/ui/js/vendor/caddyfile'
        }
    });

    $(document).ready(function() {
        let currentFile = null;
        let editor = null;

        // --- Monaco + grammar wiring ---------------------------------------
        // The 'caddyfile' module (the vendored Monarch grammar) is a loaded
        // dependency of the require below, so the 'caddyfile' and
        // 'opnware-json' languages are registered before the editor is
        // created with language 'caddyfile'. No TextMate runtime, no wasm.

        let wordWrapState = window.localStorage.getItem('opnware-editor-wrap') || 'on';
        let minimapState = (window.localStorage.getItem('opnware-editor-minimap') === 'true');
        let fontSizeState = parseInt(window.localStorage.getItem('opnware-editor-fontsize') || '13', 10);

        function updateToolbarUI() {
            if (wordWrapState === 'on') {
                $('#btn-toggle-wrap').addClass('active');
            } else {
                $('#btn-toggle-wrap').removeClass('active');
            }
            if (minimapState) {
                $('#btn-toggle-minimap').addClass('active');
            } else {
                $('#btn-toggle-minimap').removeClass('active');
            }
        }

        require(['vs/editor/editor.main', 'caddyfile'], function(monaco) {
            window.opnwareMonaco = monaco;

            editor = monaco.editor.create(document.getElementById('editor-container'), {
                value: document.getElementById('editor-content').value,
                language: 'caddyfile',
                theme: preferredEditorTheme(),
                automaticLayout: true,
                minimap: { enabled: minimapState },
                fontSize: fontSizeState,
                tabSize: 2,
                wordWrap: wordWrapState,
                scrollBeyondLastLine: false,
                lineNumbersMinChars: 3
            });

            syncEditorTheme();
            updateToolbarUI();

            // Keep the hidden textarea (the save transport) in sync with the
            // Monaco model so the existing save flow works unchanged.
            editor.onDidChangeModelContent(function() {
                document.getElementById('editor-content').value = editor.getValue();
            });

            editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function() {
                $("#save-editor").click();
            });
        });

        $('#btn-toggle-wrap').click(function() {
            wordWrapState = (wordWrapState === 'on') ? 'off' : 'on';
            window.localStorage.setItem('opnware-editor-wrap', wordWrapState);
            if (editor) {
                editor.updateOptions({ wordWrap: wordWrapState });
            }
            updateToolbarUI();
        });

        $('#btn-toggle-minimap').click(function() {
            minimapState = !minimapState;
            window.localStorage.setItem('opnware-editor-minimap', minimapState ? 'true' : 'false');
            if (editor) {
                editor.updateOptions({ minimap: { enabled: minimapState } });
            }
            updateToolbarUI();
        });

        $('#btn-font-dec').click(function() {
            if (fontSizeState > 9) {
                fontSizeState--;
                window.localStorage.setItem('opnware-editor-fontsize', fontSizeState);
                if (editor) {
                    editor.updateOptions({ fontSize: fontSizeState });
                }
            }
        });

        $('#btn-font-inc').click(function() {
            if (fontSizeState < 24) {
                fontSizeState++;
                window.localStorage.setItem('opnware-editor-fontsize', fontSizeState);
                if (editor) {
                    editor.updateOptions({ fontSize: fontSizeState });
                }
            }
        });

        function preferredEditorTheme() {
            const saved = window.localStorage.getItem('opnware-editor-theme');
            // Map legacy stored values ('opnware-vs' / 'opnware-vs-dark' from
            // the TextMate-era extended themes) to the stock themes so users
            // keep their choice.
            if (saved === 'opnware-vs') {
                return 'vs';
            }
            if (saved === 'opnware-vs-dark') {
                return 'vs-dark';
            }
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
            if ($('#editor-theme').data('selectpicker')) {
                $('#editor-theme').selectpicker('refresh');
            }
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

        // Set the current document in both the transport textarea and Monaco.
        function setEditorValue(content) {
            $("#editor-content").val(content);
            if (editor) {
                editor.setValue(content || '');
            }
        }

        // --- jstree file tree ----------------------------------------------

        function loadTree() {
            $.getJSON("/api/caddyadvanced/editor/list", function(data) {
                if (data.status !== "ok") {
                    showError(data.message);
                    return;
                }
                const nodes = [];
                if (data.caddyfile) {
                    nodes.push({
                        id: 'Caddyfile',
                        text: 'Caddyfile',
                        type: 'file',
                        data: {path: 'Caddyfile'}
                    });
                }
                nodes.push(convertTree(data.tree));
                if ($('#editor-tree').hasClass('jstree')) {
                    $('#editor-tree').jstree('destroy').empty();
                }
                // Show the managed files without requiring a click on conf.d.
                $('#editor-tree').one('ready.jstree', function() {
                    $(this).jstree('open_all');
                    if (!currentFile && data.caddyfile) {
                        $(this).jstree('select_node', 'Caddyfile');
                    }
                });
                $('#editor-tree').jstree({
                    core: {
                        data: nodes,
                        themes: { name: 'default' },
                        // jstree's core.worker defaults to true and spawns a
                        // blob: worker for background parsing. This page's CSP
                        // extension would allow it, but parsing is cheap for a
                        // small config tree, so keep it disabled.
                        worker: false
                    },
                    types: {
                        'directory': { icon: 'fa fa-folder-open-o' },
                        'file': { icon: 'fa fa-file-text-o' }
                    },
                    contextmenu: { items: contextMenuItems },
                    plugins: ['contextmenu', 'types', 'wholerow']
                });
                // jstree('destroy') unbinds the .jstree event namespace, so a
                // one-time select_node binding dies with the first recreate
                // (after add/rename/delete the tree no longer opens files).
                // Re-bind after every (re)create.
                $('#editor-tree').on('select_node.jstree', onTreeSelect);
            });
        }

        // Left-clicking a file loads it; directories just expand/collapse.
        function onTreeSelect(e, selected) {
            const node = selected.node;
            if (node && node.type === 'file' && node.data && node.data.path) {
                loadFile(node.data.path);
            }
        }

        function convertTree(node) {
            const out = {
                id: node.path,
                text: node.name,
                type: node.type,
                data: {path: node.path}
            };
            if (node.children && node.children.length) {
                out.children = node.children.map(convertTree);
            }
            return out;
        }

        // Only files may be dragged, and only into directories.
        function contextMenuItems(node) {
            const items = {};
            if (node.type === 'directory') {
                items.newFile = {
                    label: "{{ lang._('New file here') }}",
                    action: function() { addFileIn(node.data.path); }
                };
            }
            if (node.type === 'file') {
                // Left-click opens a file; the context menu only carries
                // mutations (rename, delete). The Caddyfile is never mutated.
                if (node.id !== 'Caddyfile') {
                    items.rename = {
                        label: "{{ lang._('Rename') }}",
                        action: function() { renameFile(node.data.path); }
                    };
                    items.delete = {
                        label: "{{ lang._('Delete') }}",
                        action: function() { deleteFile(node.data.path); }
                    };
                }
            }
            return items;
        }

        function addFileIn(dirPath) {
            const name = window.prompt(
                "{{ lang._('New file name in') }} " + (dirPath || 'conf.d') + "/",
                'site.caddy'
            );
            if (!name || !name.trim()) {
                return;
            }
            $("#editor-error-msg").hide();
            const path = (dirPath || 'conf.d') + '/' + name.trim();
            $.post("/api/caddyadvanced/editor/add", {path: path}, function(data) {
                if (data.status !== "ok") {
                    showError(data.message);
                    return;
                }
                loadTree();
            });
        }

        function renameFile(path) {
            const dir = path.lastIndexOf('/') > 0 ? path.substring(0, path.lastIndexOf('/')) : 'conf.d';
            const oldName = path.substring(path.lastIndexOf('/') + 1);
            const name = window.prompt("{{ lang._('Rename to') }}", oldName);
            if (!name || !name.trim() || name.trim() === oldName) {
                return;
            }
            $("#editor-error-msg").hide();
            const target = dir + '/' + name.trim();
            $.post('/api/caddyadvanced/editor/move', {path: path, target: target}, function(data) {
                if (data.status !== 'ok') {
                    showError(data.message);
                    return;
                }
                // The open editor still points at the old name; re-point it at
                // the renamed file so a Save cannot stage a phantom duplicate
                // under the old path (which would fail validation).
                if (currentFile === path) {
                    currentFile = target;
                    $("#editor-name").text(name.trim());
                }
                loadTree();
            });
        }

        function loadFile(path) {
            $.getJSON("/api/caddyadvanced/editor/get", {path: path}, function(data) {
                if (data.status !== "ok") {
                    showError(data.message);
                    return;
                }
                currentFile = path;
                $("#editor-name").text(data.name);
                setEditorValue(data.content || '');
            });
        }

        function deleteFile(path) {
            if (!confirm("{{ lang._('Delete this file?') }}")) {
                return;
            }
            $("#editor-error-msg").hide();
            $.post("/api/caddyadvanced/editor/delete", {path: path}, function(data) {
                if (data.status !== "ok") {
                    showError(data.message);
                    return;
                }
                if (currentFile === path) {
                    currentFile = null;
                    setEditorValue('');
                    $("#editor-name").text('');
                }
                loadTree();
            });
        }

        $("#save-editor").click(function() {
            if (!currentFile) {
                return;
            }
            $("#editor-error-msg").hide();
            $.post("/api/caddyadvanced/editor/save", {
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
            $("#editor-error-msg").hide();
            $.post("/api/caddyadvanced/editor/add", {path: 'conf.d/' + name}, function(data) {
                if (data.status !== "ok") {
                    showError(data.message);
                    return;
                }
                $("#new-file-name").val('');
                loadTree();
            });
        });

        function showError(message) {
            $("#editor-error-msg").html(
                '<i class="fa fa-times"></i> ' +
                $('<div>').text(message || "{{ lang._('Error') }}").html()
            ).show();
            setTimeout(function() {
                $("#editor-error-msg").fadeOut(500);
            }, 4000);
        }

        function showSuccess(message) {
            updateStatus();
        }

        function updateStatus() {
            $.getJSON("/api/caddyadvanced/editor/status", function(data) {
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
                // The rollback segment is only meaningful when a rollback
                // actually happened; hiding it when not avoids a redundant
                // "· no" right before a "no changes to save" message.
                if (data.rollback === true) {
                    $status.find("#status-rollback").text("{{ lang._('yes') }}");
                    $status.find("#status-rollback-seg").show();
                } else {
                    $status.find("#status-rollback-seg").hide();
                }
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
            $.post("/api/caddyadvanced/env/reveal", {name: row.name}, function(data) {
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
                    const $toggle = $('<button type="button" class="btn btn-xs btn-default" title="{{ lang._('Show / hide value') }}">')
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
            $.post("/api/caddyadvanced/env/save", {rows: payload}, function(data) {
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
            $.getJSON("/api/caddyadvanced/env/get", function(data) {
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

<ul class="nav nav-tabs opnware-editor-tabs" role="tablist">
    <li class="active"><a href="#editor-files-tab" data-toggle="tab">{{ lang._('Files') }}</a></li>
    <li><a href="#editor-environment-tab" data-toggle="tab">{{ lang._('Environment') }}</a></li>
</ul>

<div class="content-box tab-content opnware-tab-pane">
<div id="editor-files-tab" class="tab-pane fade in active">
    <div class="opnware-editor-split">
        <div class="opnware-editor-tree">
            <h2>{{ lang._('Files') }}</h2>
            <div id="editor-tree"></div>
            <div class="form-group __mt">
                <input id="new-file-name" type="text" class="form-control input-sm" placeholder="site.caddy">
            </div>
            <button id="add-editor" type="button" class="btn btn-primary btn-sm">{{ lang._('Add to conf.d') }}</button>
            <span class="help-block">{{ lang._('The tree contains Caddyfile and conf.d/*.caddy. Click a file to open it, and right-click to rename or delete. The root Caddyfile cannot be renamed or deleted.') }}</span>
        </div>
        <div class="opnware-editor-main">
            <div class="row" style="margin-bottom: 10px;">
                <div class="col-md-7"><h2 id="editor-name" style="margin-top: 0;">{{ lang._('Caddyfile') }}</h2></div>
                <div class="col-md-5 text-right" style="display: flex; align-items: center; justify-content: flex-end; gap: 8px;">
                    <div class="btn-group btn-group-xs" role="group" style="margin-right: 5px;">
                        <button type="button" class="btn btn-default" id="btn-toggle-wrap" title="{{ lang._('Toggle Word Wrap') }}">
                            <i class="fa fa-align-left"></i>
                        </button>
                        <button type="button" class="btn btn-default" id="btn-toggle-minimap" title="{{ lang._('Toggle Minimap') }}">
                            <i class="fa fa-map-o"></i>
                        </button>
                        <button type="button" class="btn btn-default" id="btn-font-dec" title="{{ lang._('Decrease Font Size') }}">
                            <i class="fa fa-minus"></i>
                        </button>
                        <button type="button" class="btn btn-default" id="btn-font-inc" title="{{ lang._('Increase Font Size') }}">
                            <i class="fa fa-plus"></i>
                        </button>
                    </div>
                    <select id="editor-theme" class="selectpicker" data-width="110px">
                        <option value="vs">{{ lang._('Light') }}</option>
                        <option value="vs-dark">{{ lang._('Dark') }}</option>
                    </select>
                </div>
            </div>
            <div id="editor-container" style="height: 450px; border: 1px solid #1d2733; border-radius: 4px; overflow: hidden;"></div>
            {# Hidden transport for the existing save cycle — the Monaco model mirrors its value. #}
            <textarea id="editor-content" class="form-control" rows="20" spellcheck="false"
                      style="font-family: monospace; display: none;"></textarea>
            <div class="opnware-editor-actions">
                <hr/>
                <button id="save-editor" type="button" class="btn btn-primary"><b>{{ lang._('Save') }}</b> <small style="font-weight: normal; opacity: 0.85;">(Ctrl+S / ⌘S)</small></button>
                <span id="editor-error-msg" class="text-danger __ml" style="display: none; font-weight: bold;"></span>
                <span id="editor-status" class="text-muted __ml">
                    {{ lang._('Last save') }}: <span id="status-last-save">-</span>
                    · <span id="status-result">-</span>
                    <span id="status-rollback-seg">· <span id="status-rollback">-</span></span>
                    · <span id="status-message">-</span>
                </span>
            </div>
            <span class="help-block">{{ lang._('Saving validates the full Caddy configuration before applying changes. Invalid configuration is rejected without modifying files.') }}</span>
        </div>
    </div>
</div>

<div id="editor-environment-tab" class="tab-pane fade">
    <h2>{{ lang._('Environment') }}</h2>
    <p class="help-block">
        {{ lang._('Environment variables are passed to the Caddy process through the envfile (--envfile). Secret rows are masked by default, and can be inspected using the reveal button. The plugin-managed CADDY_LOG_LEVEL row cannot be edited. The envfile is separate from the file tree above and is never shown there.') }}
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
    <div class="opnware-editor-actions">
        <hr/>
        <button id="env-add-row" type="button" class="btn btn-primary"><b>{{ lang._('Add row') }}</b></button>
        <button id="env-save" type="button" class="btn btn-primary __ml"><b>{{ lang._('Save env') }}</b></button>
        <div id="env-result" class="alert" style="display:none; margin-top: 10px;"></div>
    </div>
</div>
</div>