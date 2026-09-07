<?php

/**
 *    Copyright (C) 2026 Nils Mietzen
 *
 *    All rights reserved.
 *
 *    Redistribution and use in source and binary forms, with or without
 *    modification, are permitted provided that the following conditions are met:
 *
 *    1. Redistributions of source code must retain the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *
 *    2. Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *
 *    THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 *    INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 *    AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 *    AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 *    OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 *    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 *    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 *    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *    POSSIBILITY OF SUCH DAMAGE.
 */

function docker_services()
{
    $services = array();

    $services[] = array(
        'description' => gettext('Docker Container Engine'),
        'configd' => array(
            'restart' => array('docker restart'),
            'start' => array('docker start'),
            'stop' => array('docker stop'),
        ),
        'name' => 'docker',
        'pidfile' => '/var/run/os-docker/docker_service.pid'
    );

    return $services;
}

function docker_configure()
{
    return array(
        'bootup' => array('docker_configure_do'),
        'early' => array('docker_configure_do'),
    );
}

function docker_configure_do($verbose = false)
{
    configd_run('template reload OPNsense/Docker');
    configd_run('docker setup');
}

function docker_syslog()
{
    $logfacilities = array();
    $logfacilities['docker'] = array(
        'facility' => array('docker')
    );
    return $logfacilities;
}

function docker_xmlrpc_sync()
{
    $result = array();
    $result[] = array(
        'description' => gettext('Docker Container Engine'),
        'section' => 'OPNsense.docker',
        'id' => 'docker',
        'services' => ['docker'],
    );
    return $result;
}

function docker_firewall($fw)
{
    global $config;

    // Register child PF anchors for dynamic port redirection & NAT
    $fw->registerAnchor('opnware-docker/*', 'rdr', 0, 'head');
    $fw->registerAnchor('opnware-docker/*', 'nat', 0, 'head');
    $fw->registerAnchor('opnware-docker/*', 'fw', 0, 'head');

    // Register microVM outbound NAT pass rules on WAN
    $subnet = (string)($config['OPNsense']['docker']['general']['subnet'] ?? '100.64.0.0/24');
    $fw->registerFilterRule(
        10,
        array(
            'interface' => 'any',
            'from' => $subnet,
            'to' => 'any',
            'descr' => 'Pass microVM and container traffic to WAN/LAN',
            'direction' => 'in',
            'quick' => true,
        )
    );
}
