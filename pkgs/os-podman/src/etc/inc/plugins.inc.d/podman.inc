<?php

/*
 * Copyright (C) 2026 Nils Stein
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

function podman_services()
{
    $services = array();

    $services[] = array(
        'description' => gettext('Podman Container Engine'),
        'configd' => array(
            'restart' => array('podman restart'),
            'start' => array('podman start'),
            'stop' => array('podman stop'),
        ),
        'name' => 'podman',
        'pidfile' => '/var/run/podman/podman_service.pid'
    );

    return $services;
}

function podman_configure()
{
    return array(
        'bootup' => array('podman_configure_do'),
        'early' => array('podman_configure_do'),
    );
}

function podman_configure_do($verbose = false)
{
    configd_run('template reload OPNsense/Podman');
    configd_run('podman setup');
}

function podman_syslog()
{
    $logfacilities = array();
    $logfacilities['podman'] = array(
        'facility' => array('podman')
    );
    return $logfacilities;
}

function podman_xmlrpc_sync()
{
    $result = array();
    $result[] = array(
        'description' => gettext('Podman Container Engine'),
        'section' => 'OPNsense.podman',
        'id' => 'podman',
        'services' => ['podman'],
    );
    return $result;
}

function podman_firewall($fw)
{
    global $config;

    $interfaces = [];
    if (isset($config['OPNsense']['podman']['general']['interfaces'])) {
        $raw = (string)$config['OPNsense']['podman']['general']['interfaces'];
        $interfaces = array_filter(explode(',', $raw));
    }
    if (empty($interfaces)) {
        $interfaces = ['lan'];
    }

    // 1. Dynamic CNI port forwarding anchors
    $fw->registerAnchor('cni-rdr/*', 'rdr', 0, 'head');
    $fw->registerAnchor('cni-rdr/*', 'nat', 0, 'head');
    $fw->registerAnchor('cni-rdr/*', 'fw', 0, 'head');

    // 2. Outbound container traffic pass rule (DNS, Internet, LAN routing)
    $fw->registerFilterRule(
        10,
        [
            'type' => 'pass',
            'quick' => true,
            'direction' => 'in',
            'from' => '10.88.0.0/16',
            'to' => 'any',
            'statetype' => 'keep',
            'descr' => 'Allow outbound traffic from Podman container networks',
            '#ref' => 'ui/podman/general'
        ]
    );

    // 3. Outbound NAT on WAN interfaces for container networks
    $wanInterfaces = [];
    if (!empty($config['interfaces'])) {
        foreach ($config['interfaces'] as $intfKey => $intfConfig) {
            if (!empty($intfConfig['enable']) && (!empty($intfConfig['gateway']) || $intfKey === 'wan')) {
                $wanInterfaces[] = $intfKey;
            }
        }
    }
    if (empty($wanInterfaces)) {
        $wanInterfaces = ['wan'];
    }

    foreach ($wanInterfaces as $wanIntf) {
        $fw->registerSNatRule(
            150,
            [
                'interface' => $wanIntf,
                'from' => '10.88.0.0/16',
                'to' => 'any',
                'descr' => 'Outbound NAT for Podman container networks',
                '#ref' => 'ui/podman/general'
            ]
        );
    }

    // 4. Inbound container port access on selected interfaces
    foreach ($interfaces as $intf) {
        $fw->registerFilterRule(
            10,
            [
                'interface' => $intf,
                'statetype' => 'keep',
                'direction' => 'in',
                'from' => 'any',
                'to' => '(self)',
                'descr' => "Allow access to Podman container published ports on {$intf}",
                '#ref' => 'ui/podman/general'
            ]
        );
    }
}
