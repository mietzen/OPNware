<?php

namespace OPNsense\Caddy;

use OPNsense\Base\IndexController;

class DockerProxyController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Caddy/docker_proxy');
        $this->view->dockerProxyForm = $this->getForm("dockerproxy");
    }
}
