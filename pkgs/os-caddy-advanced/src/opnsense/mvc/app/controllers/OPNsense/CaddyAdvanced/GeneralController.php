<?php

namespace OPNsense\CaddyAdvanced;

use OPNsense\Base\IndexController;
use OPNsense\Core\Backend;

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
     *
     * The module list comes from the same status-details source the status
     * box on this page consumes; the result is cached for a short TTL so a
     * page render never shells out to caddy.
     * @return bool
     */
    private function dockerProxyModuleInstalled()
    {
        $cacheFile = '/var/db/os-caddy-advanced/modules_cache.json';
        $ttl = 300;

        $cached = null;
        if (is_file($cacheFile)) {
            $cached = json_decode(file_get_contents($cacheFile), true);
        }
        if (is_array($cached) && isset($cached['fetched_at']) && (time() - $cached['fetched_at']) < $ttl) {
            return !empty($cached['docker_proxy']);
        }

        $data = json_decode((new Backend())->configdRun('caddyadvanced status-details'), true);
        $dockerProxy = false;
        if (is_array($data) && isset($data['modules']) && is_array($data['modules'])) {
            foreach ($data['modules'] as $module) {
                if (strpos($module, 'docker_proxy') !== false) {
                    $dockerProxy = true;
                    break;
                }
            }
        }
        if (!is_dir('/var/db/os-caddy-advanced')) {
            @mkdir('/var/db/os-caddy-advanced', 0755, true);
        }
        @file_put_contents($cacheFile, json_encode(array(
            'docker_proxy' => $dockerProxy,
            'fetched_at' => time(),
        )));
        return $dockerProxy;
    }
}
