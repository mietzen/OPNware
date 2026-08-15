{#
 # OPNware os-homer — YAML Config Editor
 #
 # Edits /usr/local/www/homer/config.yml (the user-owned Homer dashboard
 # config) ONLY. The plugin-owned Caddyfile is settings-generated and is
 # never shown or edited here. Saving YAML-parses and validates the content
 # BEFORE anything is written; invalid YAML is rejected with the parser error
 # surfaced inline. No service reload happens on save: Homer re-reads
 # config.yml in the browser on every page load.
 #
 # The editor is Monaco (vendored, no CDN) with YAML syntax highlighting from
 # Monaco's built-in basic language (vs/basic-languages/monaco.contribution
 # registers it) — no TextMate grammar is needed for YAML. The vendor tree is
 # shipped by build.sh; see docs/design/shared-editor-vendor.md.
 #}

<script src="/ui/js/vendor/monaco/vs/loader.js"></script>
<script>
    // Monaco's AMD loader (vs/loader.js) resolves module ids through these
    // paths. Everything is vendored under /opnsense/www/js/vendor/ (served as
    // /ui/js/vendor/...); see docs/design/shared-editor-vendor.md.
    require.config({
        paths: {
            vs: '/ui/js/vendor/monaco/vs'
        }
    });

    $(document).ready(function() {
        let editor = null;

        // --- Monaco + built-in YAML language ---------------------------------

        // vs/basic-languages/monaco.contribution registers the built-in
        // 'yaml' language (lazily loaded chunk); no TextMate grammar needed.
        require(['vs/editor/editor.main', 'vs/basic-languages/monaco.contribution'], function(monaco) {
            editor = monaco.editor.create(document.getElementById('editor-container'), {
                value: '',
                language: 'yaml',
                theme: 'vs-dark',          // consistent with the OPNsense dark UI
                automaticLayout: true,
                minimap: { enabled: false },
                fontSize: 13,
                tabSize: 2,
                wordWrap: 'on',
                scrollBeyondLastLine: false,
                lineNumbersMinChars: 3
            });

            loadConfig();
        });

        function loadConfig() {
            $.getJSON("/api/homer/config/get", function(data) {
                if (data.status !== "ok") {
                    showError(data.message || "{{ lang._('Error') }}");
                    return;
                }
                if (editor) {
                    editor.setValue(data.content || '');
                }
                if (!data.exists) {
                    $("#config-notice").text(
                        "{{ lang._('config.yml does not exist yet — it will be created on first save.') }}"
                    ).show();
                }
            });
        }

        $("#save-config").click(function() {
            $("#editor-result").hide();
            $.post("/api/homer/config/save", {
                content: editor ? editor.getValue() : ''
            }, function(data) {
                if (data.status === "ok") {
                    showSuccess(data.message || "{{ lang._('Saved') }}");
                    if (data.parser_warning) {
                        showWarning(
                            (data.parser_message || data.message) + " " +
                            "{{ lang._('No full YAML parser is available; saving was allowed on a best-effort structural check.') }}"
                        );
                    } else {
                        $("#config-notice").hide();
                    }
                } else {
                    showError(data.message || JSON.stringify(data));
                }
            });
        });

        function showError(message) {
            const $box = $("#editor-result");
            $box.removeClass("alert-success alert-warning").addClass("alert-danger");
            $box.text(message || "{{ lang._('Error') }}");
            $box.show();
        }

        function showWarning(message) {
            const $box = $("#editor-result");
            $box.removeClass("alert-success alert-danger").addClass("alert-warning");
            $box.text(message);
            $box.show();
        }

        function showSuccess(message) {
            const $box = $("#editor-result");
            $box.removeClass("alert-danger alert-warning").addClass("alert-success");
            $box.text(message);
            $box.show();
        }
    });
</script>

<div id="config-notice" class="alert alert-info" style="display:none;"></div>
<div id="editor-result" class="alert" style="display:none;"></div>

<div class="content-box">
    <h2>{{ lang._('Homer config.yml') }}</h2>
    <p><code>/usr/local/www/homer/config.yml</code></p>
    <div id="editor-container" style="height: 480px; border: 1px solid #1d2733; border-radius: 4px; overflow: hidden;"></div>
    <div style="margin-top:10px;">
        <button id="save-config" type="button" class="btn btn-primary">{{ lang._('Save') }}</button>
    </div>
    <span class="help-block">
        {{ lang._('Saving YAML-parses and validates the content before writing. Invalid YAML is rejected and nothing is written. Homer re-reads config.yml in the browser — no service reload happens on save.') }}
    </span>
</div>
