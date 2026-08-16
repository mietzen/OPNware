#!/usr/local/bin/php
<?php

/*
 * OPNware os-caddy — sync the docker-proxy connection/TLS env vars into the envfile.
 *
 * The envfile (/usr/local/etc/caddy/env) is user-owned (managed as a masked
 * grid on the editor page). Like setup.php (CADDY_LOG_LEVEL), this script
 * owns a fixed set of env var names — the CADDY_DOCKER_* connection/TLS
 * knobs of caddy-docker-proxy plus the DOCKER_HOST / DOCKER_TLS_VERIFY
 * Docker client overrides. Every owned row is rewritten from the
 * dockerproxy config section on each run; owned rows that are no longer set
 * in the config (or the whole section) are removed, while all other rows
 * (user rows and CADDY_LOG_LEVEL) are preserved. The file is rewritten
 * atomically (temp + rename) with 0600 permissions.
 *
 * The script is wired into the reconfigure flow (configd action
 * "caddy dockerproxy-sync"); it no-ops cleanly when the dockerproxy section
 * is absent, so the flow is safe on setups that never use the feature.
 */

use OPNsense\Core\Config;

require_once 'config.inc';
require_once 'envfile.php';

/**
 * Plugin-owned env var names. Rows with these names are rewritten or removed
 * on every run; nothing else in the envfile is ever touched.
 */
$owned = array(
    'CADDY_DOCKER_PROXY_MODE',
    'CADDY_DOCKER_SOCKETS',
    'CADDY_DOCKER_CERTS_PATH',
    'CADDY_DOCKER_INGRESS_NETWORKS',
    'CADDY_DOCKER_CADDYFILE_PATH',
    'CADDY_DOCKER_ENVFILE',
    'DOCKER_HOST',
    'DOCKER_TLS_VERIFY',
);

$config = Config::getInstance()->object();

// No dockerproxy section configured — nothing to sync.
if (!isset($config->OPNsense->caddyadvanced->dockerproxy)) {
    echo 'OK';
    exit(0);
}

$dockerproxy = $config->OPNsense->caddyadvanced->dockerproxy;

// The envfile is the plugin-managed one (general.EnvFile), same file setup.php
// and the editor grid operate on.
$envfile = envfile_path();

if ($envfile === '') {
    echo 'OK';
    exit(0);
}

$enabled = isset($dockerproxy->enabled) ? (string)$dockerproxy->enabled : '0';

$rows = array();
if ($enabled === '1') {
    if (isset($dockerproxy->mode) && (string)$dockerproxy->mode !== '') {
        $rows['CADDY_DOCKER_PROXY_MODE'] = (string)$dockerproxy->mode;
    }
    if (isset($dockerproxy->docker_sockets) && (string)$dockerproxy->docker_sockets !== '') {
        $rows['CADDY_DOCKER_SOCKETS'] = (string)$dockerproxy->docker_sockets;
    }
    if (isset($dockerproxy->docker_certs_path) && (string)$dockerproxy->docker_certs_path !== '') {
        $rows['CADDY_DOCKER_CERTS_PATH'] = (string)$dockerproxy->docker_certs_path;
    }
    if (isset($dockerproxy->ingress_networks) && (string)$dockerproxy->ingress_networks !== '') {
        $rows['CADDY_DOCKER_INGRESS_NETWORKS'] = (string)$dockerproxy->ingress_networks;
    }
    if (isset($dockerproxy->caddyfile_path) && (string)$dockerproxy->caddyfile_path !== '') {
        $rows['CADDY_DOCKER_CADDYFILE_PATH'] = (string)$dockerproxy->caddyfile_path;
    }
    if (isset($dockerproxy->envfile) && (string)$dockerproxy->envfile !== '') {
        $rows['CADDY_DOCKER_ENVFILE'] = (string)$dockerproxy->envfile;
    }
    if (isset($dockerproxy->docker_host) && (string)$dockerproxy->docker_host !== '') {
        $rows['DOCKER_HOST'] = (string)$dockerproxy->docker_host;
    }
    if (isset($dockerproxy->docker_tls_verify)) {
        $rows['DOCKER_TLS_VERIFY'] = ((string)$dockerproxy->docker_tls_verify === '1') ? '1' : '0';
    }
}

$lock = envfile_acquire();
if ($lock === false) {
    echo 'ERROR: cannot acquire envfile lock';
    exit(1);
}

$lines = envfile_read_rows($envfile);

// Keep every non-owned row, drop owned rows that are not set in the config.
envfile_unset_rows($lines, $owned);

foreach ($rows as $name => $value) {
    envfile_set_row($lines, $name, $value);
}

$error = envfile_write_atomic($envfile, $lines);

envfile_release($lock);

if ($error !== null) {
    echo "ERROR: $error";
    exit(1);
}

echo 'OK';
exit(0);
