<?php

namespace OPNsense\Terminal\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelClass = '\OPNsense\Terminal\Terminal';
    protected static $internalModelName = 'terminal';
    protected static $internalModelPath = 'general';
}
