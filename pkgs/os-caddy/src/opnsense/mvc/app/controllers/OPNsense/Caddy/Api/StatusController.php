<?php

namespace OPNsense\Caddy\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

class StatusController extends ApiControllerBase
{
    public function indexAction()
    {
        $backend = new Backend();
        $result = $backend->configdRun('caddy status-details');
        $data = json_decode($result, true);
        if (!is_array($data)) {
            return ['running' => false, 'error' => trim($result)];
        }
        return $data;
    }
}
