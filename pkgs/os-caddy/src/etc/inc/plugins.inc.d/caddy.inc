<?php

/*
 * OPNware os-caddy — service registration for the OPNsense Services page,
 * the XMLRPC sync and the core Diagnostics log viewer.
 */

function caddy_services()
{
    global $config;

    $services = array();

    if (
        isset($config['OPNsense']['caddy']['general']['enabled']) &&
        $config['OPNsense']['caddy']['general']['enabled'] == 1
    ) {
        $services[] = array(
            'description' => gettext('Caddy'),
            'configd' => array(
                'restart' => array('caddy restart'),
                'start' => array('caddy start'),
                'stop' => array('caddy stop'),
            ),
            'name' => 'caddy',
            'pidfile' => '/var/run/caddy/caddy.pid'
        );
    }

    return $services;
}

function caddy_xmlrpc_sync()
{
    $result = array();

    $result[] = array(
        'description' => gettext('Caddy'),
        'section' => 'OPNsense.caddy',
        'id' => 'caddy',
        'services' => ["caddy"],
    );

    return $result;
}

function caddy_syslog()
{
    return ['caddy' => ['facility' => ['caddy']]];
}
