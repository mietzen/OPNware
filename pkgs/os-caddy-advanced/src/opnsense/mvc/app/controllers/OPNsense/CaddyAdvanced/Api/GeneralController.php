<?php

namespace OPNsense\CaddyAdvanced\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'caddyadvanced';
    protected static $internalModelClass = 'OPNsense\CaddyAdvanced\CaddyAdvanced';
}
