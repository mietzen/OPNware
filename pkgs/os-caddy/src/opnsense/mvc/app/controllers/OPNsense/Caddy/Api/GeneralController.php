<?php

namespace OPNsense\Caddy\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'caddy';
    protected static $internalModelClass = 'OPNsense\Caddy\Caddy';
}
