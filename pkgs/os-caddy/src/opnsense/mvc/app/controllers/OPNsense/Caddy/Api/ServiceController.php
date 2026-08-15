<?php

namespace OPNsense\Caddy\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Caddy\Caddy';
    protected static $internalServiceTemplate = 'OPNsense/Caddy';
    protected static $internalServiceEnabled = 'general.enabled';
    protected static $internalServiceName = 'caddy';

    public function reconfigureAction()
    {
        $backend = new Backend();

        $template = $backend->configdRun('template reload OPNsense/Caddy');
        if ($template !== 'OK') {
            return ['status' => 'failure', 'message' => $template];
        }

        $envfile = $backend->configdRun('caddy setup');
        if ($envfile !== 'OK') {
            return ['status' => 'failure', 'message' => $envfile];
        }

        $dockerproxy = $backend->configdRun('caddy dockerproxy-sync');
        if ($dockerproxy !== 'OK') {
            return ['status' => 'failure', 'message' => $dockerproxy];
        }

        return $this->reload();
    }
}
