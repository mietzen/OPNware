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
 # registers it) — no custom grammar is needed for YAML. The vendor tree is
 # shipped by build.sh; see docs/design/shared-editor-vendor.md.
 #}

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
            vs: '/ui/js/vendor/monaco/vs'
        }
    });

    $(document).ready(function() {
        let editor = null;

        // --- Monaco + built-in YAML language ---------------------------------

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

        // vs/basic-languages/monaco.contribution registers the built-in
        // 'yaml' language (lazily loaded chunk); no custom grammar needed.
        require(['vs/editor/editor.main', 'vs/basic-languages/monaco.contribution'], function(monaco) {
            window.opnwareHomerMonaco = monaco;
            editor = monaco.editor.create(document.getElementById('editor-container'), {
                value: '',
                language: 'yaml',
                theme: preferredEditorTheme(),
                automaticLayout: true,
                minimap: { enabled: minimapState },
                fontSize: fontSizeState,
                tabSize: 2,
                wordWrap: wordWrapState,
                scrollBeyondLastLine: false,
                lineNumbersMinChars: 3
            });

            editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function() {
                $("#save-config").click();
            });

            syncEditorTheme();
            updateToolbarUI();
            loadConfig();
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
            const saved = window.localStorage.getItem('opnware-homer-editor-theme');
            if (saved === 'vs' || saved === 'vs-dark') {
                return saved;
            }
            return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
                ? 'vs-dark' : 'vs';
        }

        function syncEditorTheme() {
            if (!editor || !window.opnwareHomerMonaco) {
                return;
            }
            var theme = preferredEditorTheme();
            window.opnwareHomerMonaco.editor.setTheme(theme);
            if (theme === 'vs-dark') {
                $('#theme-toggle-icon').removeClass('fa-moon-o').addClass('fa-sun-o');
                $('#btn-toggle-theme').attr('title', '{{ lang._("Switch to Light Theme") }}');
            } else {
                $('#theme-toggle-icon').removeClass('fa-sun-o').addClass('fa-moon-o');
                $('#btn-toggle-theme').attr('title', '{{ lang._("Switch to Dark Theme") }}');
            }
        }

        $('#btn-toggle-theme').click(function() {
            var current = preferredEditorTheme();
            var next = (current === 'vs-dark') ? 'vs' : 'vs-dark';
            window.localStorage.setItem('opnware-homer-editor-theme', next);
            syncEditorTheme();
        });

        if (window.matchMedia) {
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function() {
                if (!window.localStorage.getItem('opnware-homer-editor-theme')) {
                    syncEditorTheme();
                }
            });
        }

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
                    $("#config-notice").show();
                }
            });
        }

        $(window).on('keydown', function(e) {
            if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S' || e.keyCode === 83)) {
                e.preventDefault();
                $("#save-config").click();
            }
        });

        $("#save-config").click(function() {
            $("#save-status-msg").empty();
            $.post("/api/homer/config/save", {
                content: editor ? editor.getValue() : ''
            }, function(data) {
                if (data.status === "ok") {
                    showSuccess(data.message || "{{ lang._('Saved') }}");
                    $("#config-notice").hide();
                } else {
                    showError(data.message || JSON.stringify(data));
                }
            });
        });

        function showError(message) {
            $("#save-status-msg").html(
                '<span class="text-danger"><i class="fa fa-times"></i> ' +
                $('<div>').text(message || "{{ lang._('Error') }}").html() +
                '</span>'
            );
        }

        function showSuccess(message) {
            $("#save-status-msg").html(
                '<span class="text-success"><i class="fa fa-check"></i> ' +
                $('<div>').text(message || "{{ lang._('Saved') }}").html() +
                '</span>'
            );
            setTimeout(function() {
                $("#save-status-msg").fadeOut(500, function() {
                    $(this).empty().show();
                });
            }, 3000);
        }
    });
</script>

<div class="content-box opnware-homer-config-pane" style="padding: 15px;">
    <div class="row" style="margin-bottom: 10px; display: flex; align-items: center; justify-content: space-between;">
        <div style="flex: 1; min-width: 0;">
            <h2 style="margin-top: 0; margin-bottom: 0; line-height: 30px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{ lang._('Homer config.yml') }}</h2>
        </div>
        <div style="flex: 0 0 auto; text-align: center; padding: 0 10px;">
            <div class="btn-group btn-group-xs" role="group">
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
                <button type="button" class="btn btn-default" id="btn-toggle-theme" title="{{ lang._('Toggle Dark / Light Theme') }}">
                    <i class="fa fa-sun-o" id="theme-toggle-icon"></i>
                </button>
            </div>
        </div>
        <div style="flex: 1; text-align: right; display: flex; align-items: center; justify-content: flex-end; gap: 8px;">
            <span id="save-status-msg" style="font-weight: bold;"></span>
            <button id="save-config" type="button" class="btn btn-primary btn-xs" style="padding: 4px 14px; font-size: 12px;"><b>{{ lang._('Save') }}</b></button>
        </div>
    </div>
    <div id="editor-container" style="height: 520px; border: 1px solid #1d2733; border-radius: 4px; overflow: hidden;"></div>
    <span id="config-notice" class="text-info" style="margin-top: 8px; display:none;">
        <i class="fa fa-info-circle"></i> {{ lang._('config.yml does not exist yet — it will be created on first save.') }}
    </span>
    <span class="help-block" style="margin-top: 8px;">
        {{ lang._('Saving YAML-parses and validates the content before writing. Invalid YAML is rejected and nothing is written. Homer re-reads config.yml in the browser — no service reload happens on save.') }}
    </span>
</div>
