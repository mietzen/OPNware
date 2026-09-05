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
const CADDY_HOMER_DISABLED = CADDY_CONF_DIR . '/homer.caddy.disabled';

// If os-homer is being deinstalled, clean up conf.d and exit
if (!file_exists('/usr/local/opnsense/version/homer')) {
    if (file_exists(CADDY_HOMER_FILE)) {
        @unlink(CADDY_HOMER_FILE);
    }
    if (file_exists(CADDY_HOMER_DISABLED)) {
        @unlink(CADDY_HOMER_DISABLED);
    }
    if (homer_caddy_is_present()) {
        @shell_exec('/usr/sbin/service caddy reload >/dev/null 2>&1');
    }
    exit(0);
}

$caddyPresent = homer_caddy_is_present();
$mdl = new Homer();
$homerEnabled = ((string)$mdl->general->enabled === '1');

if ($caddyPresent) {
    // When Caddy Advanced is present, Homer must never run standalone
    @shell_exec('/usr/sbin/service homer onestop >/dev/null 2>&1');

    if (!is_dir(CADDY_CONF_DIR)) {
        @mkdir(CADDY_CONF_DIR, 0755, true);
    }

    // Only seed initial configuration if neither .caddy nor .disabled exists,
    // preserving any existing administrator choice across sync cycles.
    if (!file_exists(CADDY_HOMER_FILE) && !file_exists(CADDY_HOMER_DISABLED)) {
        $targetFile = $homerEnabled ? CADDY_HOMER_FILE : CADDY_HOMER_DISABLED;

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

        file_put_contents($targetFile, $content);
        @chmod($targetFile, 0644);

        if ($targetFile === CADDY_HOMER_FILE) {
            @shell_exec('/usr/sbin/service caddy reload >/dev/null 2>&1');
        }
    }

    exit(0);
}

// Restore Homer config model from conf.d when Caddy Advanced is absent or disabled
if (file_exists(CADDY_HOMER_FILE) || file_exists(CADDY_HOMER_DISABLED)) {
    $managed = $mdl->getCaddyManagedConfig();
    if (!empty($managed)) {
        if (isset($managed['Port'])) {
            $mdl->general->Port = (string)$managed['Port'];
        }
        if (isset($managed['TlsEnabled'])) {
            $mdl->general->TlsEnabled = (string)$managed['TlsEnabled'];
        }
        if (isset($managed['Interface'])) {
            $mdl->general->Interface = (string)$managed['Interface'];
        }
        if (isset($managed['ServerName'])) {
            $mdl->general->ServerName = (string)$managed['ServerName'];
        }
        if (isset($managed['enabled'])) {
            $mdl->general->enabled = (string)$managed['enabled'];
        }
        $mdl->serializeToConfig();
        Config::getInstance()->save();
    }

    // Only clean up drop-in files if Caddy Advanced package is completely uninstalled
    if (!file_exists('/usr/local/opnsense/version/caddy-advanced')) {
        if (file_exists(CADDY_HOMER_FILE)) {
            @unlink(CADDY_HOMER_FILE);
        }
        if (file_exists(CADDY_HOMER_DISABLED)) {
            @unlink(CADDY_HOMER_DISABLED);
        }
    }
}

// Restore standalone Homer when Caddy Advanced is absent or disabled
@shell_exec('/usr/local/sbin/configctl template reload OPNsense/Homer >/dev/null 2>&1');
$homerEnabled = ((string)$mdl->general->enabled === '1');
if ($homerEnabled) {
    @shell_exec('/usr/sbin/service homer start >/dev/null 2>&1');
}

exit(0);

