<?php

namespace OPNsense\CaddyAdvanced\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\CaddyAdvanced\CaddyAdvanced';
    protected static $internalServiceTemplate = 'OPNsense/CaddyAdvanced';
    protected static $internalServiceEnabled = 'general.enabled';
    protected static $internalServiceName = 'caddyadvanced';

    public function reconfigureAction()
    {
        $backend = new Backend();

        $template = $backend->configdRun('template reload OPNsense/CaddyAdvanced');
        if ($template !== 'OK') {
            return ['status' => 'failure', 'message' => $template];
        }

        $envfile = $backend->configdRun('caddyadvanced setup');
        if ($envfile !== 'OK') {
            return ['status' => 'failure', 'message' => $envfile];
        }

        $dockerproxy = $backend->configdRun('caddyadvanced dockerproxy-sync');
        if ($dockerproxy !== 'OK') {
            return ['status' => 'failure', 'message' => $dockerproxy];
        }

        return $this->reload();
    }
}
