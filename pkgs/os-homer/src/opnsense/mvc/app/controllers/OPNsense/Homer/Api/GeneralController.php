<?php

namespace OPNsense\Homer\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'homer';
    protected static $internalModelClass = 'OPNsense\Homer\Homer';
}
