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

    /**
     * Report stopped (not disabled) when the service is down, so the start
     * button is always available — the service can be run independently of
     * the enabled checkbox, matching manual caddy control.
     */
    public function statusAction()
    {
        $backend = new Backend();
        $response = $backend->configdRun('caddyadvanced status');

        if (strpos($response, 'is running') > 0) {
            $status = 'running';
        } else {
            $status = 'stopped';
        }

        return [
            'status' => $status,
            'widget' => [
                'caption_restart' => gettext('Restart'),
                'caption_start' => gettext('Start'),
                'caption_stop' => gettext('Stop'),
            ],
        ];
    }

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

        // Start/reload/stop the service based on the enabled setting and the
        // current run state — mirrors ApiMutableServiceControllerBase's
        // reconfigure logic (this controller overrides it to add the envfile
        // and docker-proxy sync steps above).
        if ($this->serviceEnabled()) {
            if ($this->statusAction()['status'] != 'running') {
                $backend->configdRun('caddyadvanced start');
            } else {
                $backend->configdRun('caddyadvanced reload');
            }
        } else {
            $backend->configdRun('caddyadvanced stop');
        }

        return ['status' => 'ok'];
    }
}
