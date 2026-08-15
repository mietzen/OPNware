{#
 # OPNware os-caddy — Docker Proxy connection/TLS settings
 #
 # The caddy-docker-proxy module (module id caddy.docker_proxy, package
 # github.com/lucaslorentz/caddy-docker-proxy) connects the caddy binary to a
 # Docker daemon. These settings only make sense when that module is compiled
 # in, so the page asks the status API for the installed non-standard modules
 # first: without the module the form is hidden and a notice points at the
 # Modules page. With it, the settings are edited and applied through the
 # standard save -> reconfigure flow. On reconfigure the plugin syncs the
 # values into the envfile as CADDY_DOCKER_* / DOCKER_* rows; tuning knobs
 # that are not modeled here stay raw envfile entries.
 #}

<script>
    $(document).ready(function() {
        function isDockerProxyModule(modules) {
            return (modules || []).some(function(m) {
                return m === 'caddy.docker_proxy' || m === 'caddy.docker-proxy' ||
                    m.indexOf('caddy.docker_proxy.') === 0 ||
                    m.indexOf('caddy.docker-proxy.') === 0;
            });
        }

        $.getJSON("/api/caddy/status", function(data) {
            if (!isDockerProxyModule(data.modules)) {
                $("#dockerproxy-missing").show();
                $("#dockerproxy-settings").hide();
                return;
            }
            $("#dockerproxy-settings").show();
            mapDataToFormUI({'frm_dockerproxy': "/api/caddy/dockerproxy/get"}).done(function() {
                $('.selectpicker').selectpicker('refresh');
            });
            bindApply();
        });

        function bindApply() {
            $('[id^="save_dockerproxy-"]').each(function () {
                const $btn = $(this);
                const formId = this.id.replace(/^save_/, 'frm_');

                $btn.attr({
                    'data-label'    : "{{ lang._('Apply') }}",
                    'data-endpoint' : "/api/caddy/service/reconfigure",
                    'data-service-widget' : "caddy"
                });

                $btn.SimpleActionButton({
                    onPreAction: function () {
                        const dfObj = new $.Deferred();

                        saveFormToEndpoint(
                            "/api/caddy/dockerproxy/set",
                            formId,
                            function () {
                                dfObj.resolve();
                            },
                            true,
                            function () {
                                dfObj.reject();
                            }
                        );
                        return dfObj.promise();
                    }
                });
            });
        }
    });
</script>

<div id="dockerproxy-missing" class="alert alert-warning" style="display:none;">
    <h2>{{ lang._('caddy-docker-proxy module not detected') }}</h2>
    <p>{{ lang._('The caddy-docker-proxy module is not compiled into the caddy binary. Add it on the Modules page (github.com/lucaslorentz/caddy-docker-proxy) and rebuild; the connection settings appear here once the module is present.') }}</p>
</div>

<div id="dockerproxy-settings" style="display:none;">
    <ul id="dockerproxyTabsHeader" class="nav nav-tabs" role="tablist">
        {{ partial("layout_partials/base_tabs_header", ['formData': dockerProxyForm]) }}
    </ul>

    <div id="dockerproxyTabsContent" class="content-box tab-content">
        {{ partial("layout_partials/base_tabs_content", ['formData': dockerProxyForm]) }}
    </div>
</div>
