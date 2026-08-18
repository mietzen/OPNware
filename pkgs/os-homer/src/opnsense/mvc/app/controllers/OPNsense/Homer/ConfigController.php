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
     * Make this editor page allow Monaco's native blob: workers and its
     * inline codicon font. OPNsense's default CSP has no worker-src/font-src,
     * so blob: workers fall back to script-src 'self' (no blob:) and data:
     * fonts to default-src 'self' (no data:). Merged into the page's CSP
     * header by ControllerBase. See docs/design/shared-editor-vendor.md.
     */
    protected array $content_security_policy = [
        "worker-src" => "blob:",
        "font-src" => "data:",
    ];

    public function indexAction()
    {
        $this->view->pick('OPNsense/Homer/config');
    }
}
