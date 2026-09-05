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

use OPNsense\Core\Backend;
use OPNsense\Core\Config;
use OPNsense\Homer\Homer;

const CADDY_CONF_DIR = '/usr/local/etc/caddy/conf.d';
const CADDY_HOMER_FILE = CADDY_CONF_DIR . '/homer.caddy';

$backend = new Backend();

// If os-homer is being deinstalled, clean up conf.d and exit
if (!file_exists('/usr/local/opnsense/version/homer')) {
    if (file_exists(CADDY_HOMER_FILE)) {
        @unlink(CADDY_HOMER_FILE);
        if (homer_caddy_is_present()) {
            $status = $backend->configdRun('caddyadvanced status');
            if (strpos($status, 'is running') !== false) {
                $backend->configdRun('caddyadvanced reload');
            }
        }
    }
    exit(0);
}

$caddyPresent = homer_caddy_is_present();
if ($caddyPresent) {
    // When Caddy Advanced is present, Homer must never run standalone
    @shell_exec('/usr/sbin/service homer stop >/dev/null 2>&1');

    if (!is_dir(CADDY_CONF_DIR)) {
        @mkdir(CADDY_CONF_DIR, 0755, true);
    }

    // Only generate initial conf.d/homer.caddy if it does not already exist,
    // preserving any user customizations made directly or via Caddyfile editor.
    if (!file_exists(CADDY_HOMER_FILE)) {
        $mdl = new Homer();
        $port = (string)$mdl->general->Port ?: '9443';
        $tls = (string)$mdl->general->TlsEnabled === '1';
        $serverName = trim((string)$mdl->general->ServerName);
        $interface = (string)$mdl->general->Interface ?: 'all';

        $listen = ':' . $port;
        if ($serverName !== '') {
            $cleanHost = (strpos($serverName, ':') !== false && $serverName[0] !== '[') ? "[{$serverName}]" : $serverName;
            $listen = $cleanHost . ':' . $port;
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

        // Reload master Caddy service only if running
        $status = $backend->configdRun('caddyadvanced status');
        if (strpos($status, 'is running') !== false) {
            $backend->configdRun('caddyadvanced reload');
        }
    }

    exit(0);
}

// Caddy Advanced is absent or disabled: clean up conf.d/homer.caddy
if (file_exists(CADDY_HOMER_FILE)) {
    @unlink(CADDY_HOMER_FILE);
}

// Restore standalone Homer
$mdl = new Homer();
$homerEnabled = (string)$mdl->general->enabled === '1';
@shell_exec('/usr/local/sbin/configctl template reload OPNsense/Homer >/dev/null 2>&1');
if ($homerEnabled) {
    @shell_exec('/usr/sbin/service homer start >/dev/null 2>&1');
}

exit(0);
