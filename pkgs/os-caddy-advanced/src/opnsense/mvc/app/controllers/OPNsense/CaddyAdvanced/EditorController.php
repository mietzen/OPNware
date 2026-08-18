<?php

namespace OPNsense\CaddyAdvanced;

use OPNsense\Base\IndexController;

class EditorController extends IndexController
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
        $this->view->pick('OPNsense/CaddyAdvanced/editor');
    }
}