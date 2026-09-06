<?php

namespace OPNsense\Terminal;

use OPNsense\Base\IndexController as BaseIndexController;

class IndexController extends BaseIndexController
{
    public function indexAction()
    {
        $this->view->generalForm = $this->getForm("general");
        $this->view->pick('OPNsense/Terminal/index');
    }
}
