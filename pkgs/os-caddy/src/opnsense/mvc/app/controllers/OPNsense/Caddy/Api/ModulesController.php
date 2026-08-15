<?php

namespace OPNsense\Caddy\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class ModulesController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'caddy';
    protected static $internalModelClass = 'OPNsense\Caddy\Caddy';

    /**
     * Expose only the declared module set (general.Modules) to the UI.
     * @return array
     * @throws \ReflectionException
     */
    protected function getModelNodes()
    {
        $result = [];
        $node = $this->getModel()->getNodeByReference('general.Modules');
        $result['general'] = ['Modules' => $node != null ? (string)$node : ''];
        return $result;
    }

    /**
     * The modules script writes its JSON result to modules_result.json; on a
     * non-zero exit configd swallows the output ("Execute error"), so fall
     * back to that file for the real result.
     * @return array
     */
    private function resultOr($result)
    {
        $data = json_decode($result, true);
        if (is_array($data)) {
            return $data;
        }
        $file = '/var/db/os-caddy/modules_result.json';
        $data = is_file($file) ? json_decode(file_get_contents($file), true) : null;
        if (is_array($data)) {
            return $data;
        }
        return ['ok' => false, 'message' => trim($result)];
    }

    /**
     * Rebuild the caddy binary from the declared module set, pinned to the
     * installed caddy version (configd action "modules modules-rebuild").
     * @return array
     */
    public function rebuildAction()
    {
        $backend = new Backend();
        return $this->resultOr($backend->configdRun('modules modules-rebuild'));
    }

    /**
     * Self-healing check: rebuild only when the stored build fingerprint no
     * longer matches the installed binary or a declared module is missing
     * (configd action "modules modules-ensure").
     * @return array
     */
    public function ensureAction()
    {
        $backend = new Backend();
        return $this->resultOr($backend->configdRun('modules modules-ensure'));
    }

    /**
     * Current non-standard modules (from the status script) plus the stored
     * build fingerprint and the last rebuild/ensure result.
     * @return array
     */
    public function statusAction()
    {
        $backend = new Backend();
        $result = $backend->configdRun('caddy status-details');
        $data = json_decode($result, true);
        if (!is_array($data)) {
            $data = ['running' => false, 'error' => trim($result)];
        }

        $data['fingerprint'] = '';
        if (is_file('/var/db/os-caddy/build.fingerprint')) {
            $data['fingerprint'] = trim(file_get_contents('/var/db/os-caddy/build.fingerprint'));
        }

        $data['last_result'] = null;
        if (is_file('/var/db/os-caddy/modules_result.json')) {
            $data['last_result'] = json_decode(file_get_contents('/var/db/os-caddy/modules_result.json'), true);
        }

        return $data;
    }
}