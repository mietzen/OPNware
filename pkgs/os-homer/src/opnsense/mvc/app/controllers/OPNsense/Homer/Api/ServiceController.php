<?php

namespace OPNsense\Homer\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

require_once 'plugins.inc.d/homer.inc';

/**
 * Homer service orchestration. When Caddy Advanced is detected, status
 * reflects the master Caddy service. Otherwise, Homer manages its own daemon.
 */
class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Homer\Homer';
    protected static $internalServiceTemplate = 'OPNsense/Homer';
    protected static $internalServiceEnabled = 'general.enabled';
    protected static $internalServiceName = 'homer';

    public function statusAction()
    {
        $status = 'stopped';

        if (homer_caddy_is_present()) {
            $homerRunning = false;
            $homerCaddyFile = '/usr/local/etc/caddy/conf.d/homer.caddy';

            if (file_exists($homerCaddyFile)) {
                $backend = new Backend();
                $response = $backend->configdRun('caddyadvanced status');
                if (strpos($response, 'is running') !== false) {
                    $homerRunning = true;
                }
            }

            return [
                'status' => $homerRunning ? 'running' : 'stopped',
                'running' => $homerRunning,
                'widget' => [
                    'caption_restart' => gettext('Restart'),
                    'caption_start' => gettext('Start'),
                    'caption_stop' => gettext('Stop'),
                ],
            ];
        }

        $backend = new Backend();
        $response = $backend->configdRun('homer status');
        $status = (strpos($response, 'is running') !== false) ? 'running' : 'stopped';

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
        if (homer_caddy_is_present()) {
            $backend = new Backend();
            $backend->configdRun('homer sync-caddy');
            return ['status' => 'ok'];
        }

        return parent::reconfigureAction();
    }
}
