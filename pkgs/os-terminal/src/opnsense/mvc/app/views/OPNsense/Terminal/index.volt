<link rel="stylesheet" href="{{ cache_safe('/ui/css/vendor/terminal/xterm.css') }}">
<script src="{{ cache_safe('/ui/js/vendor/terminal/xterm.js') }}"></script>
<script src="{{ cache_safe('/ui/js/vendor/terminal/addon-fit.js') }}"></script>

<style>
.tab-content.content-box {
    padding-top: 0 !important;
}
.nav-tabs {
    margin-bottom: 0 !important;
}
.terminal-card {
    background-color: #181818;
    border: 1px solid #2a2a2a;
    border-radius: 4px;
    padding: 12px;
    margin-top: 10px;
}
.terminal-toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    background-color: #202020;
    border: 1px solid #2a2a2a;
    border-bottom: none;
    border-top-left-radius: 4px;
    border-top-right-radius: 4px;
    padding: 8px 12px;
}
#xterm-container {
    background-color: #181818;
    border: 1px solid #2a2a2a;
    border-bottom-left-radius: 4px;
    border-bottom-right-radius: 4px;
    padding: 8px;
    min-height: 520px;
    height: calc(100vh - 280px);
    width: 100%;
}
#terminal-wrapper:fullscreen,
#terminal-wrapper:-webkit-full-screen,
#terminal-wrapper:-moz-full-screen,
.terminal-fullscreen {
    position: fixed !important;
    top: 0 !important;
    left: 0 !important;
    right: 0 !important;
    bottom: 0 !important;
    width: 100vw !important;
    height: 100vh !important;
    z-index: 2147483647 !important;
    padding: 0 !important;
    margin: 0 !important;
    border-radius: 0 !important;
    background-color: #181818 !important;
    display: flex !important;
    flex-direction: column !important;
}
#terminal-wrapper:fullscreen .terminal-toolbar,
#terminal-wrapper:-webkit-full-screen .terminal-toolbar,
#terminal-wrapper:-moz-full-screen .terminal-toolbar,
.terminal-fullscreen .terminal-toolbar {
    border-radius: 0 !important;
    flex: 0 0 auto !important;
    border: none !important;
    border-bottom: 1px solid #2a2a2a !important;
    background-color: #202020 !important;
    z-index: 10 !important;
}
#terminal-wrapper:fullscreen #xterm-container,
#terminal-wrapper:-webkit-full-screen #xterm-container,
#terminal-wrapper:-moz-full-screen #xterm-container,
.terminal-fullscreen #xterm-container {
    flex: 1 1 auto !important;
    height: calc(100vh - 42px) !important;
    min-height: calc(100vh - 42px) !important;
    border-radius: 0 !important;
    border: none !important;
    box-sizing: border-box !important;
    padding: 8px !important;
    overflow: hidden !important;
}
.terminal-fullscreen .xterm,
.terminal-fullscreen .xterm-screen,
.terminal-fullscreen .xterm-viewport {
    height: 100% !important;
}
body.terminal-body-fullscreen {
    overflow: hidden !important;
}
.status-pill {
    display: inline-flex;
    align-items: center;
    padding: 3px 8px;
    font-size: 11px;
    font-weight: 600;
    border-radius: 12px;
}
.status-connected {
    background-color: rgba(40, 167, 69, 0.2);
    color: #28a745;
    border: 1px solid rgba(40, 167, 69, 0.4);
}
.status-disconnected {
    background-color: rgba(220, 53, 69, 0.2);
    color: #dc3545;
    border: 1px solid rgba(220, 53, 69, 0.4);
}
.status-connecting {
    background-color: rgba(255, 193, 7, 0.2);
    color: #ffc107;
    border: 1px solid rgba(255, 193, 7, 0.4);
}
</style>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#tab-terminal" id="tab_terminal_link"><i class="fa fa-terminal"></i> {{ lang._('Terminal') }}</a></li>
    <li><a data-toggle="tab" href="#tab-settings" id="tab_settings_link"><i class="fa fa-cogs"></i> {{ lang._('Settings') }}</a></li>
</ul>

<div class="tab-content content-box">
    <!-- Terminal Tab -->
    <div id="tab-terminal" class="tab-pane fade in active">
        <div id="terminal-wrapper">
            <div class="terminal-toolbar">
                <div style="display: flex; align-items: center; gap: 10px;">
                    <span id="term-status-pill" class="status-pill status-connecting">
                        <i class="fa fa-circle-o-notch fa-spin"></i>&nbsp;{{ lang._('Connecting...') }}
                    </span>
                    <span id="term-user-info" style="color: #aaa; font-size: 12px; font-family: monospace;"></span>
                </div>
                <div style="display: flex; align-items: center; gap: 6px;">
                    <button class="btn btn-xs btn-default" id="btn_term_reconnect" title="{{ lang._('Reconnect') }}">
                        <i class="fa fa-refresh"></i> {{ lang._('Reconnect') }}
                    </button>
                    <button class="btn btn-xs btn-default" id="btn_term_clear" title="{{ lang._('Clear') }}">
                        <i class="fa fa-eraser"></i> {{ lang._('Clear') }}
                    </button>
                    <button class="btn btn-xs btn-default" id="btn_term_font_dec" title="{{ lang._('Decrease Font') }}">
                        <i class="fa fa-search-minus"></i>
                    </button>
                    <button class="btn btn-xs btn-default" id="btn_term_font_inc" title="{{ lang._('Increase Font') }}">
                        <i class="fa fa-search-plus"></i>
                    </button>
                    <button class="btn btn-xs btn-default" id="btn_term_fullscreen" title="{{ lang._('Toggle Fullscreen') }}">
                        <i class="fa fa-expand"></i>
                    </button>
                </div>
            </div>
            <div id="xterm-container"></div>
        </div>
    </div>

    <!-- Settings Tab -->
    <div id="tab-settings" class="tab-pane fade">
        {{ partial("layout_partials/base_form",['fields':generalForm,'id':'frm_general-settings'])}}
        <div class="col-md-12">
            <hr/>
            <button class="btn btn-primary" id="btn_save_settings" type="button">
                <b>{{ lang._('Save') }}</b> <i id="btn_save_progress" class=""></i>
            </button>
        </div>

        <div class="col-md-12" style="margin-top: 25px;">
            <div class="panel panel-default">
                <div class="panel-heading">
                    <h3 class="panel-title">{{ lang._('Available Shells & Package Management') }}</h3>
                </div>
                <div class="panel-body">
                    <table class="table table-striped table-condensed" id="tbl-shells">
                        <thead>
                            <tr>
                                <th>{{ lang._('Shell') }}</th>
                                <th>{{ lang._('Path') }}</th>
                                <th>{{ lang._('Status') }}</th>
                                <th style="width: 120px;">{{ lang._('Action') }}</th>
                            </tr>
                        </thead>
                        <tbody id="tbl-shells-body">
                            <tr><td colspan="4"><i class="fa fa-spinner fa-spin"></i> {{ lang._('Loading shell status...') }}</td></tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
$(document).ready(function() {
    var term = null;
    var fitAddon = null;
    var ws = null;
    var currentFontSize = 13;
    var isFullscreen = false;
    var reconnectTimer = null;

    function getWsProtocol() {
        return window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    }

    function initTerminal() {
        if (term !== null) {
            return;
        }

        var themePalette = {
            background: '#181818',
            foreground: '#f0f0f0',
            cursor: '#5af78e',
            cursorAccent: '#181818',
            selectionBackground: '#334455',
            black: '#181818',
            red: '#ff5555',
            green: '#50fa7b',
            yellow: '#f1fa8c',
            blue: '#bd93f9',
            magenta: '#ff79c6',
            cyan: '#8be9fd',
            white: '#f8f8f2',
            brightBlack: '#6272a4',
            brightRed: '#ff6e6e',
            brightGreen: '#69ff94',
            brightYellow: '#ffffa5',
            brightBlue: '#d6acff',
            brightMagenta: '#ff92df',
            brightCyan: '#a4ffff',
            brightWhite: '#ffffff'
        };

        term = new Terminal({
            cursorBlink: true,
            fontSize: currentFontSize,
            fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
            lineHeight: 1.15,
            theme: themePalette,
            scrollback: 5000,
            macOptionIsMeta: false,
            macOptionClickForcesSelection: false
        });

        term.attachCustomKeyEventHandler(function(e) {
            if (e.type !== 'keydown') {
                return true;
            }

            // Filter dead key / IME composition events to prevent duplicate backtick inputs
            if (e.isComposing || e.key === 'Dead') {
                return false;
            }

            if (e.metaKey && e.key === 'ArrowLeft') {
                if (ws && ws.readyState === WebSocket.OPEN) {
                    ws.send('\x01');
                }
                return false;
            }

            if (e.metaKey && e.key === 'ArrowRight') {
                if (ws && ws.readyState === WebSocket.OPEN) {
                    ws.send('\x05');
                }
                return false;
            }

            if (e.altKey && e.key === 'ArrowLeft') {
                if (ws && ws.readyState === WebSocket.OPEN) {
                    ws.send('\x1bb');
                }
                return false;
            }

            if (e.altKey && e.key === 'ArrowRight') {
                if (ws && ws.readyState === WebSocket.OPEN) {
                    ws.send('\x1bf');
                }
                return false;
            }

            if (e.metaKey && e.key === 'Backspace') {
                if (ws && ws.readyState === WebSocket.OPEN) {
                    ws.send('\x15');
                }
                return false;
            }

            if (e.altKey && e.key === 'Backspace') {
                if (ws && ws.readyState === WebSocket.OPEN) {
                    ws.send('\x17');
                }
                return false;
            }

            if (e.metaKey && (e.key === 'k' || e.key === 'K')) {
                if (term) {
                    term.clear();
                }
                if (ws && ws.readyState === WebSocket.OPEN) {
                    ws.send('\x0c');
                }
                return false;
            }

            return true;
        });

        if (window.FitAddon && window.FitAddon.FitAddon) {
            fitAddon = new window.FitAddon.FitAddon();
            term.loadAddon(fitAddon);
        }

        var container = document.getElementById('xterm-container');
        term.open(container);

        if (fitAddon) {
            fitAddon.fit();
        }

        term.onData(function(data) {
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send(data);
            }
        });

        term.onResize(function(size) {
            if (ws && ws.readyState === WebSocket.OPEN) {
                var resizeMsg = '\x00' + JSON.stringify({
                    type: 'resize',
                    cols: size.cols,
                    rows: size.rows
                });
                ws.send(resizeMsg);
            }
        });

        connectWebSocket();
    }

    var heartbeatTimer = null;
    var autoReconnectTimer = null;
    var reconnectAttempts = 0;

    function clearHeartbeat() {
        if (heartbeatTimer) {
            clearInterval(heartbeatTimer);
            heartbeatTimer = null;
        }
    }

    function startHeartbeat() {
        clearHeartbeat();
        heartbeatTimer = setInterval(function() {
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send('\x00{"type":"ping"}');
            }
        }, 15000);
    }

    function connectWebSocket(reset) {
        clearTimeout(autoReconnectTimer);
        clearHeartbeat();

        if (ws) {
            try { ws.close(); } catch(e) {}
            ws = null;
        }

        var statusPill = $('#term-status-pill');
        statusPill.attr('class', 'status-pill status-connecting')
                  .html('<i class="fa fa-circle-o-notch fa-spin"></i>&nbsp;{{ lang._("Connecting...") }}');

        var wsUrl = getWsProtocol() + '//' + window.location.host + '/api/terminal/ws' + (reset ? '?reset=1' : '');

        try {
            ws = new WebSocket(wsUrl);
            ws.binaryType = 'arraybuffer';

            ws.onopen = function() {
                reconnectAttempts = 0;
                startHeartbeat();
                statusPill.attr('class', 'status-pill status-connected')
                          .html('<i class="fa fa-check-circle"></i>&nbsp;{{ lang._("Connected") }}');
                $('#term-user-info').text('host');
                if (term) {
                    term.focus();
                    if (fitAddon) {
                        try {
                            fitAddon.fit();
                            var resizeMsg = '\x00' + JSON.stringify({
                                type: 'resize',
                                cols: term.cols,
                                rows: term.rows
                            });
                            ws.send(resizeMsg);
                        } catch(e) {}
                    }
                }
            };

            ws.onmessage = function(event) {
                if (term) {
                    if (event.data instanceof ArrayBuffer) {
                        term.write(new Uint8Array(event.data));
                    } else if (typeof event.data === 'string') {
                        if (!event.data.startsWith('\x00{')) {
                            term.write(event.data);
                        }
                    }
                }
            };

            ws.onerror = function(err) {
                clearHeartbeat();
                statusPill.attr('class', 'status-pill status-disconnected')
                          .html('<i class="fa fa-exclamation-triangle"></i>&nbsp;{{ lang._("Error") }}');
            };

            ws.onclose = function() {
                clearHeartbeat();
                statusPill.attr('class', 'status-pill status-disconnected')
                          .html('<i class="fa fa-times-circle"></i>&nbsp;{{ lang._("Disconnected") }}');

                // Auto-reconnect if terminal tab is active
                var activeTab = $('#maintabs li.active a').attr('href');
                if (activeTab === '#tab-terminal' || !activeTab) {
                    reconnectAttempts++;
                    var delay = Math.min(1500 * Math.pow(1.3, reconnectAttempts), 8000);
                    clearTimeout(autoReconnectTimer);
                    autoReconnectTimer = setTimeout(function() {
                        if ($('#maintabs li.active a').attr('href') === '#tab-terminal') {
                            connectWebSocket(false);
                        }
                    }, delay);
                }
            };
        } catch(e) {
            clearHeartbeat();
            statusPill.attr('class', 'status-pill status-disconnected')
                      .html('<i class="fa fa-times-circle"></i>&nbsp;{{ lang._("Failed to connect") }}');
        }
    }

    function refreshShellTable() {
        ajaxGet('/api/terminal/terminal/shellStatus', {}, function(data, status) {
            if (status === 'success' && data.shells) {
                var tbody = $('#tbl-shells-body');
                tbody.empty();

                $.each(data.shells, function(k, item) {
                    var tr = $('<tr></tr>');
                    tr.append($('<td></td>').text(item.display));
                    tr.append($('<td></td>').html('<code>' + item.path + '</code>'));

                    if (item.installed) {
                        tr.append($('<td></td>').html('<span class="label label-success"><i class="fa fa-check"></i> ' + '{{ lang._("Installed") }}' + '</span>'));
                        tr.append($('<td></td>').html('<span class="text-muted"><i class="fa fa-check"></i> Ready</span>'));
                    } else {
                        tr.append($('<td></td>').html('<span class="label label-default">' + '{{ lang._("Not Installed") }}' + '</span>'));
                        if (item.pkg) {
                            var btn = $('<button class="btn btn-xs btn-primary btn-install-shell" data-shell="' + item.pkg + '"><i class="fa fa-download"></i> ' + '{{ lang._("Install") }}' + '</button>');
                            tr.append($('<td></td>').append(btn));
                        } else {
                            tr.append($('<td></td>').text('-'));
                        }
                    }
                    tbody.append(tr);
                });

                $('.btn-install-shell').click(function() {
                    var shellPkg = $(this).data('shell');
                    var actName = shellPkg === 'bash' ? 'installBash' : 'installZsh';
                    var $btn = $(this);
                    $btn.prop('disabled', true).html('<i class="fa fa-spinner fa-spin"></i> ' + '{{ lang._("Installing...") }}');
                    ajaxCall('/api/terminal/service/' + actName, {}, function(data) {
                        setTimeout(refreshShellTable, 1000);
                    });
                });
            }
        });
    }

    // Button controls
    $('#btn_term_reconnect').click(function() {
        if (term) {
            term.clear();
        }
        connectWebSocket(false);
    });

    $('#btn_term_clear').click(function() {
        if (term) {
            term.clear();
        }
    });

    function updateFontSize(delta) {
        if (!term) {
            return;
        }
        var nextSize = currentFontSize + delta;
        if (nextSize >= 9 && nextSize <= 32) {
            currentFontSize = nextSize;
            if (term.options) {
                term.options.fontSize = currentFontSize;
            }
            if (typeof term.setOption === 'function') {
                try { term.setOption('fontSize', currentFontSize); } catch(e) {}
            }
            if (fitAddon) {
                setTimeout(function() {
                    try { fitAddon.fit(); } catch(e) {}
                }, 50);
            }
        }
    }

    $('#btn_term_font_inc').click(function() {
        updateFontSize(1);
    });

    $('#btn_term_font_dec').click(function() {
        updateFontSize(-1);
    });

    function isDocFullscreen() {
        return !!(document.fullscreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement);
    }

    function enableFullscreenUI() {
        isFullscreen = true;
        $('body').addClass('terminal-body-fullscreen');
        $('#terminal-wrapper').addClass('terminal-fullscreen');
        $('#btn_term_fullscreen').html('<i class="fa fa-compress"></i>');
        setTimeout(function() {
            if (fitAddon) {
                try { fitAddon.fit(); } catch(e) {}
            }
            if (term) {
                term.focus();
            }
        }, 150);
    }

    function disableFullscreenUI() {
        isFullscreen = false;
        $('body').removeClass('terminal-body-fullscreen');
        $('#terminal-wrapper').removeClass('terminal-fullscreen');
        $('#btn_term_fullscreen').html('<i class="fa fa-expand"></i>');
        setTimeout(function() {
            if (fitAddon) {
                try { fitAddon.fit(); } catch(e) {}
            }
            if (term) {
                term.focus();
            }
        }, 150);
    }

    function toggleFullscreen() {
        var wrapper = document.getElementById('terminal-wrapper');
        if (!isDocFullscreen() && !isFullscreen) {
            if (wrapper && wrapper.requestFullscreen) {
                wrapper.requestFullscreen().then(enableFullscreenUI).catch(function() {
                    enableFullscreenUI();
                });
            } else if (wrapper && wrapper.webkitRequestFullscreen) {
                wrapper.webkitRequestFullscreen();
                enableFullscreenUI();
            } else if (wrapper && wrapper.mozRequestFullScreen) {
                wrapper.mozRequestFullScreen();
                enableFullscreenUI();
            } else if (wrapper && wrapper.msRequestFullscreen) {
                wrapper.msRequestFullscreen();
                enableFullscreenUI();
            } else {
                enableFullscreenUI();
            }
        } else {
            if (document.exitFullscreen) {
                document.exitFullscreen().then(disableFullscreenUI).catch(function() {
                    disableFullscreenUI();
                });
            } else if (document.webkitExitFullscreen) {
                document.webkitExitFullscreen();
                disableFullscreenUI();
            } else if (document.mozCancelFullScreen) {
                document.mozCancelFullScreen();
                disableFullscreenUI();
            } else if (document.msExitFullscreen) {
                document.msExitFullscreen();
                disableFullscreenUI();
            } else {
                disableFullscreenUI();
            }
        }
    }

    $('#btn_term_fullscreen').click(function() {
        toggleFullscreen();
    });

    $(document).on('fullscreenchange webkitfullscreenchange mozfullscreenchange MSFullscreenChange', function() {
        if (isDocFullscreen()) {
            enableFullscreenUI();
        } else {
            disableFullscreenUI();
        }
    });

    // Resize handler
    $(window).resize(function() {
        if (fitAddon) {
            fitAddon.fit();
        }
    });

    // Tab switch handling
    $('a[data-toggle="tab"]').on('shown.bs.tab', function(e) {
        if (e.target.id === 'tab_terminal_link') {
            if (term === null) {
                initTerminal();
            } else {
                if (!ws || ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING) {
                    connectWebSocket(false);
                }
                if (fitAddon) {
                    setTimeout(function() {
                        fitAddon.fit();
                        term.focus();
                    }, 100);
                }
            }
        } else if (e.target.id === 'tab_settings_link') {
            refreshShellTable();
            loadFormData();
        }
    });

    document.addEventListener('visibilitychange', function() {
        if (!document.hidden && ($('#maintabs li.active a').attr('href') === '#tab-terminal' || !$('#maintabs li.active a').attr('href'))) {
            if (term !== null && (!ws || ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING)) {
                connectWebSocket(false);
            }
        }
    });

    // Load form data
    function loadFormData() {
        mapDataToFormUI({
            'frm_general': '/api/terminal/settings/get'
        }).done(function() {
            formatTokenizersUI();
            setTimeout(function() {
                $('.selectpicker').selectpicker('refresh');
            }, 50);
        });
    }
    loadFormData();

    // Save settings
    $('#btn_save_settings').click(function() {
        saveFormToEndpoint('/api/terminal/settings/set', 'frm_general-settings', function() {
            ajaxCall('/api/terminal/service/reconfigure', {}, function() {
                refreshShellTable();
                if (term) {
                    term.clear();
                }
                connectWebSocket(true);
            });
        });
    });

    // Service status integration
    updateServiceControlUI('terminal');

    // Auto init terminal on page load
    setTimeout(initTerminal, 150);
});
</script>
