<?php

/*
 * OPNware os-caddy-advanced — service registration for the OPNsense Services page,
 * the XMLRPC sync and the core Diagnostics log viewer.
 */

function caddyadvanced_services()
{
    // Registered unconditionally so the service can be started from the UI
    // even before it is enabled in the settings (start button on the status
    // page); pluginctl needs the entry to report a run state at all.
    $services = array();
    $services[] = array(
        'description' => gettext('Caddy'),
        'configd' => array(
            'restart' => array('caddyadvanced restart'),
            'start' => array('caddyadvanced start'),
            'stop' => array('caddyadvanced stop'),
        ),
        'name' => 'caddyadvanced',
        'pidfile' => '/var/run/caddy/caddy.pid'
    );

    return $services;
}

function caddyadvanced_xmlrpc_sync()
{
    $result = array();

    $result[] = array(
        'description' => gettext('Caddy'),
        'section' => 'OPNsense.caddyadvanced',
        'id' => 'caddyadvanced',
        'services' => ["caddyadvanced"],
    );

    return $result;
}

function caddyadvanced_syslog()
{
    return ['caddyadvanced' => ['facility' => ['caddyadvanced']]];
}

/*
 * Regenerate the plugin templates (rc.conf.d/caddy) and re-sync the envfile
 * on config apply paths that do not go through the WebUI reconfigure action —
 * config restore/import (bootup after the default reboot, local on
 * rc.reload_all) would otherwise leave the generated files stale. Mirrors
 * what ServiceController::reconfigureAction() does.
 */
function caddyadvanced_configure()
{
    return [
        'bootup' => ['caddyadvanced_configure_do'],
        'local' => ['caddyadvanced_configure_do'],
    ];
}

function caddyadvanced_configure_do($verbose = false)
{
    $backend = new \OPNsense\Core\Backend();
    $backend->configdRun('template reload OPNsense/CaddyAdvanced');
    $backend->configdRun('caddyadvanced setup');
    $backend->configdRun('caddyadvanced dockerproxy-sync');
}
