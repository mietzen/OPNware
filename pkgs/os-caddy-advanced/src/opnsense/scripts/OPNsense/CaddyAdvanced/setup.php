#!/usr/local/bin/php
<?php

/*
 * OPNware os-caddy — sync the plugin-managed env var into the envfile.
 *
 * The envfile (/usr/local/etc/caddy/env) is user-owned (managed as a masked
 * grid on the editor page). This script only ensures it exists and keeps the
 * single plugin-owned CADDY_LOG_LEVEL row in sync with the settings; all
 * other rows are left untouched. The var is available to user-authored
 * Caddyfile global options ({$CADDY_LOG_LEVEL}) without the plugin ever
 * generating Caddyfile content.
 */

use OPNsense\Core\Config;

require_once 'config.inc';
require_once 'envfile.php';

$config = Config::getInstance()->object();

$level = '';
if (isset($config->OPNsense->caddyadvanced->general->LogLevel)) {
    $level = (string)$config->OPNsense->caddyadvanced->general->LogLevel;
}

$envfile = envfile_path();
if ($envfile === '') {
    echo 'OK';
    exit(0);
}

$lock = envfile_acquire();
if ($lock === false) {
    echo 'ERROR: cannot acquire envfile lock';
    exit(1);
}

$rows = envfile_read_rows($envfile);
envfile_set_row($rows, 'CADDY_LOG_LEVEL', $level);
$error = envfile_write_atomic($envfile, $rows);

envfile_release($lock);

if ($error !== null) {
    echo "ERROR: $error";
    exit(1);
}

echo 'OK';
exit(0);
