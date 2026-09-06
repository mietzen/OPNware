<?php

function terminal_services()
{
    $services = array();
    $services[] = array(
        'description' => gettext('Web Terminal'),
        'configd' => array(
            'restart' => array('terminal restart'),
            'start' => array('terminal start'),
            'stop' => array('terminal stop'),
        ),
        'name' => 'terminal_service',
        'pidfile' => '/var/run/terminal/terminal_service.pid'
    );
    return $services;
}

function terminal_configure()
{
    return array(
        'bootup' => array('terminal_configure_do'),
    );
}

function terminal_configure_do($verbose = false)
{
    configd_run('template reload OPNsense/Terminal');
    configd_run('terminal restart');
}
