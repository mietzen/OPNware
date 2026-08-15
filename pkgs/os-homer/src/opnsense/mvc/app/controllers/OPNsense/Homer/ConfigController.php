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
    public function indexAction()
    {
        $this->view->pick('OPNsense/Homer/config');
    }
}
