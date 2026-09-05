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

        if (strpos($response, 'is running') !== false) {
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

    public function startAction()
    {
        if (file_exists('/usr/local/opnsense/version/homer')) {
            $backend = new Backend();
            $backend->configdRun('homer sync-caddy');
        }

        return parent::startAction();
    }

    public function restartAction()
    {
        if (file_exists('/usr/local/opnsense/version/homer')) {
            $backend = new Backend();
            $backend->configdRun('homer sync-caddy');
        }

        return parent::restartAction();
    }

    public function stopAction()
    {
        $response = parent::stopAction();

        if (file_exists('/usr/local/opnsense/version/homer')) {
            $backend = new Backend();
            $backend->configdRun('homer sync-caddy');
        }

        return $response;
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

        // The rc script refuses to start without a Caddyfile (required_files);
        // surface that on Apply instead of reporting ok while the service stays
        // down on a fresh install.
        if ($this->serviceEnabled() && !is_file('/usr/local/etc/caddy/Caddyfile')) {
            return ['status' => 'failure', 'message' => gettext('Caddyfile not found — create one in the editor before applying.')];
        }

        // Start/reload/stop the service based on the enabled setting and the
        // current run state — mirrors ApiMutableServiceControllerBase's
        // reconfigure logic (this controller overrides it to add the envfile
        // and docker-proxy sync steps above).
        if ($this->serviceEnabled()) {
            if (file_exists('/usr/local/opnsense/version/homer')) {
                $backend->configdRun('homer sync-caddy');
            }

            if ($this->statusAction()['status'] != 'running') {
                $backend->configdRun('caddyadvanced start');
            } else {
                $backend->configdRun('caddyadvanced reload');
            }
        } else {
            $backend->configdRun('caddyadvanced stop');

            if (file_exists('/usr/local/opnsense/version/homer')) {
                $backend->configdRun('homer sync-caddy');
            }
        }

        return ['status' => 'ok'];
    }
}
