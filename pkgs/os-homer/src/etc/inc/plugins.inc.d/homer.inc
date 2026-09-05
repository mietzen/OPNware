<?php

/*
 * OPNware os-homer — service registration for the OPNsense Services page,
 * the XMLRPC sync and the core Diagnostics log viewer.
 */

function homer_caddy_is_present(): bool
{
    if (!file_exists('/usr/local/opnsense/version/caddy-advanced')) {
        return false;
    }

    $configObj = \OPNsense\Core\Config::getInstance()->object();
    if (isset($configObj->OPNsense->caddyadvanced->general->enabled)) {
        return (string)$configObj->OPNsense->caddyadvanced->general->enabled === '1';
    }

    return false;
}

function homer_services()
{
    if (homer_caddy_is_present()) {
        return array();
    }

    // Registered unconditionally so the service can be started from the UI
    // even before it is enabled in the settings (start button on the status
    // page); pluginctl needs the entry to report a run state at all.
    $services = array();
    $services[] = array(
        'description' => gettext('Homer'),
        'configd' => array(
            'restart' => array('homer restart'),
            'start' => array('homer start'),
            'stop' => array('homer stop'),
        ),
        'name' => 'homer',
        'pidfile' => '/var/run/os-homer/homer.pid'
    );

    return $services;
}

function homer_xmlrpc_sync()
{
    $result = array();

    $result[] = array(
        'description' => gettext('Homer'),
        'section' => 'OPNsense.homer',
        'id' => 'homer',
        'services' => ["homer"],
    );

    return $result;
}

function homer_syslog()
{
    return ['homer' => ['facility' => ['homer']]];
}

function homer_configure(): array
{
    return [
        'bootup' => ['homer_caddy_sync:1'],
    ];
}

function homer_caddy_sync()
{
    require_once 'config.inc';
    @shell_exec('/usr/local/bin/php /usr/local/opnsense/scripts/OPNsense/Homer/sync_caddy.php >/dev/null 2>&1');
}
