{#
 # OPNware os-caddy — Caddyfile Editor
 #
 # The user-owned Caddy config at /usr/local/etc/caddy is a flat tree:
 # Caddyfile plus conf.d/*.caddy (the import glob is non-recursive). ACME
 # storage, autosave, certs and keys are invisible. Saving validates the
 # staged tree with `caddy validate`, applies it atomically and reloads
 # Caddy gracefully; a reload failure rolls back to the previous config.
 #}

<script>
    $(document).ready(function() {
        let currentFile = null;

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
                $("#editor-content").val(data.content || '');
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
                    $("#editor-content").val('');
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
            <textarea id="editor-content" class="form-control" rows="20" spellcheck="false"
                      style="font-family: monospace;"></textarea>
            <div style="margin-top:10px;">
                <button id="save-editor" type="button" class="btn btn-primary">{{ lang._('Save') }}</button>
            </div>
            <span class="help-block">{{ lang._('Saving validates the whole Caddy file tree first; invalid configuration is rejected without writing anything.') }}</span>
        </div>
    </div>
</div>
