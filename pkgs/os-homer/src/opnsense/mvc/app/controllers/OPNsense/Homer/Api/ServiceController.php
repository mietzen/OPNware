<?php

namespace OPNsense\Homer\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;

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
}
