<?php

namespace OPNsense\Homer;

use OPNsense\Base\BaseModel;

class Homer extends BaseModel
{
    /**
     * Parse the active Homer site configuration from Caddy conf.d.
     * Encapsulates foreign Caddyfile parsing at the model layer.
     */
    public function getCaddyManagedConfig(string $path = '/usr/local/etc/caddy/conf.d/homer.caddy'): array
    {
        $res = [];
        $content = @file_get_contents($path);

        if ($content === false || trim($content) === '') {
            $res['enabled'] = '0';
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

        $res['TlsEnabled'] = ($schema === 'https' || $port === '443' || $hasTls) ? '1' : '0';

        return $res;
    }
}
