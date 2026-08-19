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

namespace OPNsense\Podman\Api;

class SystemController extends PodmanApiControllerBase
{
    public function dfAction()
    {
        return $this->executeAction('system_df');
    }

    public function pruneAction()
    {
        if ($this->request->isPost()) {
            return $this->executeAction('system_prune');
        }
        return ["status" => "failed"];
    }

    public function infoAction()
    {
        return $this->executeAction('system_info');
    }

    public function statusAction()
    {
        $backend = new \OPNsense\Core\Backend();
        $statusRaw = trim($backend->configdRun('podman status') ?: '');
        $isRunning = (stripos($statusRaw, 'is running') !== false);

        $setupData = [];
        if (file_exists('/var/db/podman/setup_status.json')) {
            $setupData = json_decode(@file_get_contents('/var/db/podman/setup_status.json'), true) ?: [];
        }

        $version = $setupData['version'] ?? '5.8.4';

        $model = new \OPNsense\Podman\Podman();
        $general = $model->general;

        $tcpEnabled = ((string)$general->tcp_enabled === '1');
        $tlsEnabled = ((string)$general->tls_enabled === '1');
        $addr = (string)$general->listen_address ?: '127.0.0.1';
        $port = (string)$general->listen_port ?: '2376';

        $tcpEndpoint = 'Disabled';
        if ($tcpEnabled) {
            $proto = $tlsEnabled ? 'tcp (TLS)' : 'tcp';
            $tcpEndpoint = "{$proto}://{$addr}:{$port}";
        }

        $interfaces = (string)$general->interfaces ?: 'lan';
        $driver = $setupData['driver'] ?? 'zfs';
        $hasZfs = !empty($setupData['zfs']);
        $storageInfo = $hasZfs ? "ZFS (zroot/containers)" : "VFS (/var/db/containers/storage)";
        $linuxEmulation = ((string)$general->enable_linux === '1') ? 'Enabled (64-bit ABI, linprocfs, linsysfs)' : 'Disabled';

        $config = \OPNsense\Core\Config::getInstance()->object();
        $lanIp = (string)($config->interfaces->lan->ipaddr ?? '127.0.0.1');
        $sshEnabled = isset($config->system->ssh->enabled);

        return [
            'status' => $isRunning ? 'running' : 'stopped',
            'running' => $isRunning,
            'version' => $version,
            'socket' => '/var/run/podman/podman.sock',
            'storage' => $storageInfo,
            'linux_emulation' => $linuxEmulation,
            'tcp_endpoint' => $tcpEndpoint,
            'tcp_enabled' => $tcpEnabled,
            'tls_enabled' => $tlsEnabled,
            'listen_address' => $addr,
            'listen_port' => $port,
            'lan_ip' => $lanIp,
            'ssh_enabled' => $sshEnabled,
            'interfaces' => $interfaces
        ];
    }
}
