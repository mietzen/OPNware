<?php

/*
 * OPNware os-homer — service registration for the OPNsense Services page,
 * the XMLRPC sync and the core Diagnostics log viewer.
 */

function homer_services()
{
    global $config;

    $services = array();

    if (
        isset($config['OPNsense']['homer']['general']['enabled']) &&
        $config['OPNsense']['homer']['general']['enabled'] == 1
    ) {
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
    }

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
