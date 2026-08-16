<?php

namespace OPNsense\CaddyAdvanced\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class ModulesController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'caddyadvanced';
    protected static $internalModelClass = 'OPNsense\CaddyAdvanced\CaddyAdvanced';

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
        $file = '/var/db/os-caddy-advanced/modules_result.json';
        $data = is_file($file) ? json_decode(file_get_contents($file), true) : null;
        if (is_array($data)) {
            return $data;
        }
        return ['ok' => false, 'message' => trim($result)];
    }

    /**
     * The module catalog from https://caddyserver.com/api/modules, cached for
     * 24h so the page does not depend on a live outbound connection. The
     * caddyserver API returns a map of module id -> [entry]; each entry
     * carries the Go import path in "package". Only the unique non-standard
     * import paths (standard caddy modules are compiled in already) are
     * returned, sorted.
     *
     * @return array
     */
    public function catalogAction()
    {
        $cacheFile = '/var/db/os-caddy-advanced/modules_catalog.json';
        $ttl = 24 * 3600;

        $cached = null;
        if (is_file($cacheFile)) {
            $cached = json_decode(file_get_contents($cacheFile), true);
        }
        if (is_array($cached) && isset($cached['modules']) && isset($cached['fetched_at'])
            && (time() - $cached['fetched_at']) < $ttl) {
            return $cached;
        }

        $ch = curl_init('https://caddyserver.com/api/modules');
        curl_setopt_array($ch, array(
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 15,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_USERAGENT => 'OPNsense-os-caddy-advanced',
        ));
        $body = curl_exec($ch);
        $error = curl_error($ch);
        curl_close($ch);

        if ($body === false || $body === '') {
            // Stale cache beats an error — report the age so the UI can note it.
            if (is_array($cached) && isset($cached['modules'])) {
                $cached['stale'] = true;
                return $cached;
            }
            return array('status' => 'failure', 'message' => gettext('catalog fetch failed: ') . $error);
        }

        $data = json_decode($body, true);
        if (!is_array($data) || !isset($data['result']) || !is_array($data['result'])) {
            if (is_array($cached) && isset($cached['modules'])) {
                $cached['stale'] = true;
                return $cached;
            }
            return array('status' => 'failure', 'message' => gettext('unexpected catalog response'));
        }

        $packages = array();
        foreach ($data['result'] as $entries) {
            foreach ($entries as $entry) {
                if (!is_array($entry) || empty($entry['package'])) {
                    continue;
                }
                $pkg = (string)$entry['package'];
                // Standard caddy modules ship with the binary; declaring them
                // is pointless (xcaddy refuses or rebuilds identical code).
                if (strpos($pkg, 'github.com/caddyserver/caddy/v2') === 0) {
                    continue;
                }
                $packages[$pkg] = $pkg;
            }
        }
        $modules = array_values($packages);
        sort($modules, SORT_STRING);

        $result = array(
            'status' => 'ok',
            'modules' => $modules,
            'fetched_at' => time(),
        );
        @file_put_contents($cacheFile, json_encode($result));
        return $result;
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
        $result = $backend->configdRun('caddyadvanced status-details');
        $data = json_decode($result, true);
        if (!is_array($data)) {
            $data = ['running' => false, 'error' => trim($result)];
        }

        $data['fingerprint'] = '';
        if (is_file('/var/db/os-caddy-advanced/build.fingerprint')) {
            $data['fingerprint'] = trim(file_get_contents('/var/db/os-caddy-advanced/build.fingerprint'));
        }

        $data['last_result'] = null;
        if (is_file('/var/db/os-caddy-advanced/modules_result.json')) {
            $data['last_result'] = json_decode(file_get_contents('/var/db/os-caddy-advanced/modules_result.json'), true);
        }

        return $data;
    }
}