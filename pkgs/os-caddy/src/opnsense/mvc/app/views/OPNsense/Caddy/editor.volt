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
            monaco.languages.register({ id: 'caddyfile' });

            editor = monaco.editor.create(document.getElementById('editor-container'), {
                value: document.getElementById('editor-content').value,
                language: 'caddyfile',
                theme: 'vs-dark',
                automaticLayout: true,
                minimap: { enabled: false },
                fontSize: 13,
                tabSize: 2,
                wordWrap: 'on',
                scrollBeyondLastLine: false,
                lineNumbersMinChars: 3
            });

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
                $.each(data.files || [], function(i, file) {
                    const $li = $('<li>');
                    const $link = $('<a href="#">').text(file.name).click(function(e) {
                        e.preventDefault();
                        loadFile(file.path);
                    });
                    $li.append($link);
                    if (file.name !== 'Caddyfile') {
                        const $del = $('<button type="button" class="btn btn-xs btn-danger">')
                            .text("{{ lang._('Delete') }}")
                            .click(function(e) {
                                e.stopPropagation();
                                deleteFile(file.path);
                            });
                        $li.append(' ');
                        $li.append($del);
                    }
                    $list.append($li);
                });
                if (!(data.files || []).length) {
                    $list.append($('<li>').text("{{ lang._('No files yet') }}"));
                }
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

<div id="editor-status" class="content-box">
    <h2>{{ lang._('Last save / reload') }}</h2>
    <table class="table table-condensed">
        <tr><td>{{ lang._('Last save') }}</td><td id="status-last-save"></td></tr>
        <tr><td>{{ lang._('Result') }}</td><td id="status-result"></td></tr>
        <tr><td>{{ lang._('Rolled back') }}</td><td id="status-rollback"></td></tr>
        <tr><td>{{ lang._('Message') }}</td><td id="status-message"></td></tr>
    </table>
</div>

<div id="editor-result" class="alert" style="display:none;"></div>

<div class="row">
    <div class="col-md-3">
        <div class="content-box">
            <h2>{{ lang._('Files') }}</h2>
            <ul id="editor-files" class="nav nav-pills nav-stacked"></ul>
            <div class="form-inline" style="margin-top:10px;">
                <input id="new-file-name" type="text" class="form-control" placeholder="site.caddy">
                <button id="add-editor" type="button" class="btn btn-primary">{{ lang._('Add') }}</button>
            </div>
            <span class="help-block">{{ lang._('Add and delete are limited to .caddy files inside conf.d. The Caddyfile itself cannot be deleted.') }}</span>
        </div>
    </div>
    <div class="col-md-9">
        <div class="content-box">
            <h2 id="editor-name">{{ lang._('Caddyfile') }}</h2>
            <p><code id="editor-path"></code></p>
            <div id="editor-container" style="height: 480px; border: 1px solid #1d2733; border-radius: 4px; overflow: hidden;"></div>
            {# Hidden transport for the existing save cycle — the Monaco model mirrors its value. #}
            <textarea id="editor-content" class="form-control" rows="20" spellcheck="false"
                      style="font-family: monospace; display: none;"></textarea>
            <div style="margin-top:10px;">
                <button id="save-editor" type="button" class="btn btn-primary">{{ lang._('Save') }}</button>
            </div>
            <span class="help-block">{{ lang._('Saving validates the whole Caddy file tree first; invalid configuration is rejected without writing anything.') }}</span>
        </div>
    </div>
</div>
