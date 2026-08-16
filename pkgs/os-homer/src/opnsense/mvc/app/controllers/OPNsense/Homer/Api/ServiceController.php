<?php

namespace OPNsense\Homer\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

/**
 * Homer service orchestration. The base reconfigure flow stops the
 * instance, regenerates the plugin-owned Caddyfile via the configd
 * template and restarts the instance — matching the map ticket.
 */
class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Homer\Homer';
    protected static $internalServiceTemplate = 'OPNsense/Homer';
    protected static $internalServiceEnabled = 'general.enabled';
    protected static $internalServiceName = 'homer';

    /**
     * Report stopped (not disabled) when the service is down, so the start
     * button is always available — the service can be run independently of
     * the enabled checkbox, matching manual caddy control.
     */
    public function statusAction()
    {
        $backend = new Backend();
        $response = $backend->configdRun('homer status');

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
}
