<?php

/*
 * OPNware os-caddy-advanced — service registration for the OPNsense Services page,
 * the XMLRPC sync and the core Diagnostics log viewer.
 */

function caddyadvanced_services()
{
    global $config;

    $services = array();

    if (
        isset($config['OPNsense']['caddyadvanced']['general']['enabled']) &&
        $config['OPNsense']['caddyadvanced']['general']['enabled'] == 1
    ) {
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
    }

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
