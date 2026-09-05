<?php

namespace OPNsense\Homer\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

require_once 'plugins.inc.d/homer.inc';

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'homer';
    protected static $internalModelClass = 'OPNsense\Homer\Homer';

    private function parseCaddyConf(string $path): array
    {
        $res = [];
        $content = @file_get_contents($path);

        if ($content === false || trim($content) === '') {
            return $res;
        }

        $res['enabled'] = '1';

        if (preg_match('/^\s*([^\s{]+)\s*\{/m', $content, $matches)) {
            $header = trim($matches[1]);
            $schema = '';

            if (strpos($header, '://') !== false) {
                list($schema, $header) = explode('://', $header, 2);
            }

            $hasTls = (bool)preg_match('/tls\s+(internal|[^\s}]+)/', $content);
            $host = '';
            $port = ($schema === 'https' || $hasTls) ? '443' : '80';

            if (preg_match('/^\[([a-fA-F0-9:]+)\](?::([0-9]+))?$/', $header, $ipv6Match)) {
                $host = $ipv6Match[1];
                if (isset($ipv6Match[2]) && $ipv6Match[2] !== '') {
                    $port = $ipv6Match[2];
                }
            } elseif (strpos($header, ':') !== false) {
                $lastColon = strrpos($header, ':');
                $host = substr($header, 0, $lastColon);
                $port = substr($header, $lastColon + 1);
            } else {
                $host = $header;
            }

            $res['Port'] = $port;

            if ($host === '' || $host === '0.0.0.0' || $host === '::') {
                $res['Interface'] = 'all';
                $res['ServerName'] = '';
            } elseif ($host === '127.0.0.1' || $host === 'localhost' || $host === '::1') {
                $res['Interface'] = 'localhost';
                $res['ServerName'] = '';
            } elseif (filter_var($host, FILTER_VALIDATE_IP)) {
                $res['Interface'] = 'lan';
                $res['ServerName'] = '';
            } else {
                $res['Interface'] = 'all';
                $res['ServerName'] = $host;
            }
        }

        $res['TlsEnabled'] = preg_match('/tls\s+(internal|[^\s}]+)/', $content) ? '1' : '0';

        return $res;
    }

    public function getAction()
    {
        $result = parent::getAction();

        if (!homer_caddy_is_present()) {
            $result['caddy_managed'] = false;
            return $result;
        }

        $result['caddy_managed'] = true;
        $confFile = '/usr/local/etc/caddy/conf.d/homer.caddy';

        if (file_exists($confFile)) {
            $parsed = $this->parseCaddyConf($confFile);
            foreach ($parsed as $key => $val) {
                if (!isset($result[static::$internalModelName]['general'][$key])) {
                    continue;
                }

                if (is_array($result[static::$internalModelName]['general'][$key])) {
                    foreach ($result[static::$internalModelName]['general'][$key] as $optKey => $optData) {
                        $result[static::$internalModelName]['general'][$key][$optKey]['selected'] = ($optKey === $val) ? 1 : 0;
                    }
                } else {
                    $result[static::$internalModelName]['general'][$key] = $val;
                }
            }
        }

        return $result;
    }

    public function setAction()
    {
        if (homer_caddy_is_present()) {
            return array(
                'result' => 'failed',
                'message' => gettext('Settings are managed by Caddy Advanced via /usr/local/etc/caddy/conf.d/homer.caddy and cannot be modified from this form.'),
            );
        }

        if ($this->request->isPost()) {
            $post = $this->request->getPost(static::$internalModelName);
            $general = is_array($post) && isset($post['general']) ? $post['general'] : array();

            // Merge with the current model so partial updates validate against
            // the effective (already-stored) values of untouched fields.
            $mdl = $this->getModel();
            $tls = array_key_exists('TlsEnabled', $general)
                ? ((string)$general['TlsEnabled'] === '1' || $general['TlsEnabled'] === true)
                : (string)$mdl->general->TlsEnabled === '1';
            $interface = array_key_exists('Interface', $general)
                ? (string)$general['Interface']
                : (string)$mdl->general->Interface;
            $servername = array_key_exists('ServerName', $general)
                ? trim((string)$general['ServerName'])
                : trim((string)$mdl->general->ServerName);

            if ($tls && $interface !== 'all' && $servername === '') {
                return array(
                    'result' => 'failed',
                    'status' => 'failure',
                    'validations' => array(
                        // Key must match the form field's DOM id (dotted).
                        'homer.general.ServerName' => gettext('A Server name (hostname) is required when TLS is enabled and the dashboard does not listen on all interfaces.'),
                    ),
                );
            }
        }

        return parent::setAction();
    }
}
