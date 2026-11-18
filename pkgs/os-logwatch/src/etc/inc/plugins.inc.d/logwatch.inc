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

function logwatch_services()
{
    // Register unconditionally so start/stop/restart controls appear even when stopped.
    $services = [];
    $services[] = [
        'description' => gettext('Logwatch Syslog Aggregator'),
        'configd' => [
            'restart' => ['logwatch restart'],
            'start' => ['logwatch start'],
            'stop' => ['logwatch stop'],
        ],
        'name' => 'logwatch',
        'pidfile' => '/var/run/os-logwatch/logwatch.pid',
    ];

    return $services;
}

function logwatch_configure()
{
    return [
        'bootup' => ['logwatch_configure_do'],
        'local' => ['logwatch_configure_do'],
    ];
}

function logwatch_configure_do($verbose = false)
{
    global $config;

    $backend = new \OPNsense\Core\Backend();
    $enabled = (string)($config['OPNsense']['logwatch']['general']['enabled'] ?? '1') === '1';

    $backend->configdRun('template reload OPNsense/Logwatch');
    if ($enabled) {
        $backend->configdRun('logwatch start');
    }
    $backend->configdRun('logwatch setup');
}

function logwatch_syslog()
{
    return ['logwatch' => ['facility' => ['logwatch']]];
}

function logwatch_xmlrpc_sync()
{
    $result = [];
    $result[] = [
        'description' => gettext('Logwatch Syslog Aggregator'),
        'section' => 'OPNsense.logwatch',
        'id' => 'logwatch',
        'services' => ['logwatch'],
    ];

    return $result;
}

function logwatch_firewall($fw)
{
    global $config;

    $ly = $config['OPNsense']['logwatch']['general'] ?? null;
    if (empty($ly) || (string)($ly['enabled'] ?? '0') !== '1') {
        return;
    }

    if ((string)($ly['auto_firewall'] ?? '1') !== '1') {
        return;
    }

    $port = (int)($ly['listen_port'] ?? 514);
    if ($port < 1 || $port > 65535) {
        $port = 514;
    }

    $rawIntfs = (string)($ly['listen_interfaces'] ?? 'lan');
    $intfs = array_filter(array_map('trim', explode(',', $rawIntfs)));
    if (empty($intfs)) {
        $intfs = ['lan'];
    }

    $protocols = [];
    if ((string)($ly['enable_udp'] ?? '1') === '1') {
        $protocols[] = 'udp';
    }
    if ((string)($ly['enable_tcp'] ?? '1') === '1') {
        $protocols[] = 'tcp';
    }

    foreach ($intfs as $intf) {
        foreach ($protocols as $proto) {
            $fw->registerFilterRule(
                10,
                [
                    'interface' => $intf,
                    'protocol' => $proto,
                    'statetype' => 'keep',
                    'direction' => 'in',
                    'from' => 'any',
                    'to' => '(self)',
                    'to_port' => (string)$port,
                    'descr' => "Allow Logwatch syslog {$proto}/{$port} on {$intf}",
                    '#ref' => 'ui/logwatch/general',
                ]
            );
        }
    }
}
