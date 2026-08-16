<?php

namespace OPNsense\CaddyAdvanced;

use OPNsense\Base\IndexController;

class GeneralController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/CaddyAdvanced/general');
        $form = $this->getForm("general");
        if (!$this->dockerProxyModuleInstalled()) {
            // The Docker Proxy tab is only relevant when the module is in
            // the binary — drop it otherwise.
            if (isset($form['tabs'])) {
                $form['tabs'] = array_values(array_filter($form['tabs'], function ($tab) {
                    return $tab['tab_id'] !== 'general-dockerproxy';
                }));
            }
        }
        $this->view->generalForm = $form;
    }

    /**
     * Whether the caddy-docker-proxy module is present in the installed binary.
     * @return bool
     */
    private function dockerProxyModuleInstalled()
    {
        exec('/usr/local/bin/caddy list-modules --skip-standard 2>/dev/null', $out, $code);
        foreach ($out as $line) {
            if (strpos($line, 'docker_proxy') !== false) {
                return true;
            }
        }
        return false;
    }
}
