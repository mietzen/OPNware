<?php

namespace OPNsense\Caddy;

use OPNsense\Base\IndexController;

class ModulesController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Caddy/modules');
    }
}