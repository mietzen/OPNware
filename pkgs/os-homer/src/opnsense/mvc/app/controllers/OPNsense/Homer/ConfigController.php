<?php

namespace OPNsense\Homer;

use OPNsense\Base\IndexController;

/**
 * YAML config editor for the user-owned Homer dashboard config.
 *
 * The page edits /usr/local/www/homer/config.yml only. The plugin-owned
 * Caddyfile is settings-generated and is never displayed or edited here.
 */
class ConfigController extends IndexController
{
    /**
     * Editor-page CSP extension: allow Monaco's blob: workers and inline
     * codicon font on this page. Merged into the page's CSP header by
     * ControllerBase. See docs/design/shared-editor-vendor.md.
     */
    protected array $content_security_policy = [
        "worker-src" => "'self' blob:",
        "font-src" => "'self' data:",
    ];

    public function indexAction()
    {
        $this->view->pick('OPNsense/Homer/config');
    }
}
