<?php

namespace OPNsense\CaddyAdvanced;

use OPNsense\Base\IndexController;

class ModulesController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/CaddyAdvanced/modules');
    }
}