<?php

namespace OPNsense\Caddy;

use OPNsense\Base\IndexController;

class EditorController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Caddy/editor');
    }
}