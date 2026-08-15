<?php

namespace OPNsense\Caddy;

use OPNsense\Base\IndexController;

class GeneralController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Caddy/general');
        $this->view->generalForm = $this->getForm("general");
    }
}
