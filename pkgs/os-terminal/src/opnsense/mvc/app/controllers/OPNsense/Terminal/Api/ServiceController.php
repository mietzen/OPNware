<?php

namespace OPNsense\Terminal\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Terminal\Terminal';
    protected static $internalServiceTemplate = 'OPNsense/Terminal';
    protected static $internalServiceEnabled = 'general.enabled';
    protected static $internalServiceName = 'terminal';

    protected function reconfigureForceRestart()
    {
        return true;
    }

    public function statusAction()
    {
        $backend = new Backend();
        $response = $backend->configdRun('terminal status');
        $status = "stopped";
        if (strpos($response, "is running") !== false) {
            $status = "running";
        }
        return [
            "status" => $status,
            "widget" => [
                "caption_stopped" => gettext("Stopped"),
                "caption_running" => gettext("Running"),
            ]
        ];
    }
}
