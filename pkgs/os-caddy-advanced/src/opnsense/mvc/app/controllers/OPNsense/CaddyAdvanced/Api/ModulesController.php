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

    public static $defaultCatalogModules = [
        'github.com/lucaslorentz/caddy-docker-proxy/v2',
    ];

    /**
     * The module catalog from https://caddyserver.com/api/modules, cached for
     * 24h so the page does not depend on a live outbound connection. The
     * caddyserver API returns a map of module id -> [entry]; each entry
     * carries the Go import path in "package". Only the unique non-standard
     * import paths (standard caddy modules are compiled in already) are
     * returned, sorted. Curated default modules (e.g. caddy-docker-proxy)
     * are always included.
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
            foreach (self::$defaultCatalogModules as $def) {
                if (!in_array($def, $cached['modules'], true)) {
                    $cached['modules'][] = $def;
                }
            }
            sort($cached['modules'], SORT_STRING);
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
                foreach (self::$defaultCatalogModules as $def) {
                    if (!in_array($def, $cached['modules'], true)) {
                        $cached['modules'][] = $def;
                    }
                }
                sort($cached['modules'], SORT_STRING);
                $cached['stale'] = true;
                return $cached;
            }
            return array(
                'status' => 'ok',
                'modules' => self::$defaultCatalogModules,
                'stale' => true,
                'message' => gettext('catalog fetch failed: ') . $error
            );
        }

        $data = json_decode($body, true);
        if (!is_array($data) || !isset($data['result']) || !is_array($data['result'])) {
            if (is_array($cached) && isset($cached['modules'])) {
                foreach (self::$defaultCatalogModules as $def) {
                    if (!in_array($def, $cached['modules'], true)) {
                        $cached['modules'][] = $def;
                    }
                }
                sort($cached['modules'], SORT_STRING);
                $cached['stale'] = true;
                return $cached;
            }
            return array(
                'status' => 'ok',
                'modules' => self::$defaultCatalogModules,
                'stale' => true,
                'message' => gettext('unexpected catalog response')
            );
        }

        $packages = array();
        foreach (self::$defaultCatalogModules as $def) {
            $packages[$def] = $def;
        }
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
     * Set declared module set with validation against valid Go package paths.
     * @return array
     */
    public function setAction()
    {
        if ($this->request->isPost() && $this->request->hasPost(static::$internalModelName)) {
            $postData = $this->request->getPost(static::$internalModelName);
            if (isset($postData['general']['Modules'])) {
                $modulesStr = (string)$postData['general']['Modules'];
                $lines = explode("\n", $modulesStr);
                foreach ($lines as $line) {
                    $mod = trim($line);
                    if ($mod !== '' && !self::isValidModulePath($mod)) {
                        return [
                            'result' => 'failed',
                            'validations' => [
                                'general.Modules' => sprintf(gettext('Invalid module path: %s'), $mod)
                            ]
                        ];
                    }
                }
            }
        }
        return parent::setAction();
    }

    /**
     * Rebuild the caddy binary from the declared module set, pinned to the
     * installed caddy version (configd action "caddyadvanced-modules modules-rebuild").
     * @return array
     */
    public function rebuildAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failure', 'ok' => false, 'message' => gettext('Method Not Allowed')];
        }
        $backend = new Backend();
        return $this->resultOr($backend->configdRun('caddyadvanced-modules modules-rebuild'));
    }

    /**
     * Self-healing check: rebuild only when the stored build fingerprint no
     * longer matches the installed binary or a declared module is missing
     * (configd action "caddyadvanced-modules modules-ensure").
     * @return array
     */
    public function ensureAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failure', 'ok' => false, 'message' => gettext('Method Not Allowed')];
        }
        $backend = new Backend();
        return $this->resultOr($backend->configdRun('caddyadvanced-modules modules-ensure'));
    }

    public static function isValidModulePath($path)
    {
        return is_string($path)
            && preg_match('/^[a-zA-Z0-9_\.\-\/]+(@[a-zA-Z0-9_\.\-\+]+)?$/', $path) === 1
            && strpos($path, '..') === false;
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

        $data['binary_fingerprint'] = '';
        $data['moduleset_fingerprint'] = '';
        $data['fingerprint'] = '';
        if (is_file('/var/db/os-caddy-advanced/build.fingerprint')) {
            $raw = trim(file_get_contents('/var/db/os-caddy-advanced/build.fingerprint'));
            $data['fingerprint'] = $raw;
            $parts = explode(' ', $raw, 2);
            $data['binary_fingerprint'] = $parts[0] ?? '';
            $data['moduleset_fingerprint'] = $parts[1] ?? '';
        }

        $data['last_result'] = null;
        if (is_file('/var/db/os-caddy-advanced/modules_result.json')) {
            $data['last_result'] = json_decode(file_get_contents('/var/db/os-caddy-advanced/modules_result.json'), true);
        }

        return $data;
    }
}