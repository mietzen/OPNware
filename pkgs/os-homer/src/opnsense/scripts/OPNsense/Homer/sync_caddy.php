#!/usr/local/bin/php
<?php

/*
 * OPNware os-homer — synchronize Homer site configuration with Caddy Advanced.
 *
 * When os-caddy-advanced is installed, Homer's isolated caddy instance is stopped
 * and its site configuration is written into /usr/local/etc/caddy/conf.d/homer.caddy.
 * When os-caddy-advanced is absent, conf.d/homer.caddy is cleaned up and Homer's
 * isolated caddy instance is re-enabled and started.
 */

require_once 'config.inc';
require_once 'plugins.inc.d/homer.inc';

use OPNsense\Core\Config;
use OPNsense\Homer\Homer;

const CADDY_CONF_DIR = '/usr/local/etc/caddy/conf.d';
const CADDY_HOMER_FILE = CADDY_CONF_DIR . '/homer.caddy';

$caddyPresent = homer_caddy_is_present();

if ($caddyPresent) {
    if (!is_dir(CADDY_CONF_DIR)) {
        @mkdir(CADDY_CONF_DIR, 0755, true);
    }

    // Stop isolated Homer daemon if active
    @shell_exec('/usr/sbin/service homer stop >/dev/null 2>&1');

    // Generate conf.d/homer.caddy if not present
    if (!file_exists(CADDY_HOMER_FILE)) {
        $mdl = new Homer();
        $port = (string)$mdl->general->Port ?: '8085';
        $tls = (string)$mdl->general->TlsEnabled === '1';
        $serverName = trim((string)$mdl->general->ServerName);
        $interface = (string)$mdl->general->Interface ?: 'all';

        $listen = ':' . $port;
        if ($serverName !== '') {
            $listen = $serverName . ':' . $port;
        } elseif ($interface === 'localhost') {
            $listen = '127.0.0.1:' . $port;
        } elseif ($interface === 'lan') {
            $configObj = Config::getInstance()->object();
            $lanIp = isset($configObj->interfaces->lan->ipaddr) ? (string)$configObj->interfaces->lan->ipaddr : '';
            if ($lanIp !== '') {
                $listen = (strpos($lanIp, ':') !== false ? '[' . $lanIp . ']' : $lanIp) . ':' . $port;
            }
        }

        $tlsBlock = $tls ? "\ttls internal {\n\t\ton_demand\n\t}\n" : '';
        $content = "# Homer dashboard served via Caddy Advanced\n"
            . "{$listen} {\n"
            . "\troot * /usr/local/www/homer\n"
            . "\tfile_server\n"
            . $tlsBlock
            . "}\n";

        file_put_contents(CADDY_HOMER_FILE, $content);
        @chmod(CADDY_HOMER_FILE, 0644);
    }

    // Reload master Caddy service
    @shell_exec('/usr/local/sbin/configctl caddyadvanced reload >/dev/null 2>&1');
    echo "OK: Homer synced with Caddy Advanced\n";
    exit(0);
}

// Caddy Advanced is absent: clean up conf.d/homer.caddy and restore Homer
if (file_exists(CADDY_HOMER_FILE)) {
    @unlink(CADDY_HOMER_FILE);
}

@shell_exec('/usr/local/sbin/configctl template reload OPNsense/Homer >/dev/null 2>&1');

$mdl = new Homer();
if ((string)$mdl->general->enabled === '1') {
    @shell_exec('/usr/sbin/service homer start >/dev/null 2>&1');
}

echo "OK: Homer standalone service restored\n";
exit(0);
