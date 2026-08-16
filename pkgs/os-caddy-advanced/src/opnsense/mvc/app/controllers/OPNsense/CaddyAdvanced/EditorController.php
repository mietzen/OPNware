<?php

namespace OPNsense\CaddyAdvanced;

use OPNsense\Base\IndexController;

class EditorController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/CaddyAdvanced/editor');
    }
}