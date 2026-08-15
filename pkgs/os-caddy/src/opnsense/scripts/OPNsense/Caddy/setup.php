<?php

/*
 * OPNware os-caddy — sync the plugin-managed env var into the envfile.
 *
 * The envfile (/usr/local/etc/caddy/env) is user-owned (managed as a masked
 * grid on the editor page). This script only ensures it exists and keeps the
 * single plugin-owned CADDY_LOG_LEVEL row in sync with the settings; all
 * other rows are left untouched. The seeded Caddyfile references the var in
 * its global log block, so the setting reaches the process without the
 * plugin ever generating Caddyfile content.
 */

use OPNsense\Core\Config;

require_once 'config.inc';

$config = Config::getInstance()->object();

$level = '';
if (isset($config->OPNsense->caddy->general->LogLevel)) {
    $level = (string)$config->OPNsense->caddy->general->LogLevel;
}

$envfile = '/usr/local/etc/caddy/env';
if (isset($config->OPNsense->caddy->general->EnvFile)) {
    $envfile = (string)$config->OPNsense->caddy->general->EnvFile;
}

if ($envfile === '') {
    echo 'OK';
    exit(0);
}

$dir = dirname($envfile);
if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
    echo "ERROR: cannot create $dir";
    exit(1);
}

$lines = array();
if (is_file($envfile)) {
    $lines = file($envfile, FILE_IGNORE_NEW_LINES);
}

$found = false;
foreach ($lines as $i => $line) {
    if (preg_match('/^CADDY_LOG_LEVEL=/', $line)) {
        $lines[$i] = "CADDY_LOG_LEVEL=$level";
        $found = true;
    }
}
if (!$found) {
    $lines[] = "CADDY_LOG_LEVEL=$level";
}

file_put_contents($envfile, implode("\n", $lines) . "\n");
chmod($envfile, 0600);

echo 'OK';
exit(0);
