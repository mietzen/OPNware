<?php

namespace OPNsense\CaddyAdvanced;

use OPNsense\Base\IndexController;

class EditorController extends IndexController
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
        $this->view->pick('OPNsense/CaddyAdvanced/editor');
    }
}