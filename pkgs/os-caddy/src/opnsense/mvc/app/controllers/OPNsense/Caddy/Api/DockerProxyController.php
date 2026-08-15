<?php

namespace OPNsense\Caddy\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class DockerProxyController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'caddy';
    protected static $internalModelClass = 'OPNsense\Caddy\Caddy';

    /**
     * Expose only the dockerproxy section to the UI.
     * @return array
     * @throws \ReflectionException
     */
    protected function getModelNodes()
    {
        $result = [];
        $node = $this->getModel()->getNodeByReference('dockerproxy');
        if ($node != null) {
            $result['dockerproxy'] = $node->getNodes();
        }
        return $result;
    }
}
