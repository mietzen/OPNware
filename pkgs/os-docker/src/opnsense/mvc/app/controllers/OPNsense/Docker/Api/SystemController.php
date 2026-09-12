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

namespace OPNsense\Docker\Api;

class SystemController extends DockerApiControllerBase
{
    public function dfAction()
    {
        return $this->executeAction('system_df');
    }

    public function statsAction()
    {
        return $this->executeAction('system_stats');
    }

    public function infoAction()
    {
        return $this->executeAction('system_info');
    }

    public function pruneAction()
    {
        if ($this->request->isPost()) {
            return $this->executeAction('system_prune');
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }

    public function conflictsAction()
    {
        $conflictsFile = '/var/db/os-docker/conflicts.json';
        if (file_exists($conflictsFile)) {
            $data = json_decode(file_get_contents($conflictsFile), true);
            if (is_array($data)) {
                return ["status" => "ok", "conflicts" => $data];
            }
        }
        return ["status" => "ok", "conflicts" => []];
    }

    public function statusAction()
    {
        $backend = new \OPNsense\Core\Backend();
        $statusRaw = trim($backend->configdRun('docker status') ?: '');
        $isRunning = (stripos($statusRaw, 'is running') !== false);

        $version = '29.4.2';
        $verOut = trim(shell_exec('/usr/local/bin/docker --version 2>/dev/null') ?: '');
        if (!empty($verOut) && preg_match('/version\s+([^\s,]+)/i', $verOut, $m)) {
            $version = $m[1];
        }

        $model = new \OPNsense\Docker\Docker();
        $general = $model->general;

        $cpus = (string)$general->cpus ?: '2';
        $mem = (string)$general->memory ?: '2048';
        $disk = (string)$general->disk_size ?: '20';
        $portSync = ((string)$general->port_sync === '1');
        $conflictProt = ((string)$general->fail_on_conflict === '1');
        $interfaces = (string)$general->interfaces ?: 'lan';
        $subnet = (string)$general->subnet ?: '100.64.0.0/24';

        $microvmDesc = $isRunning ? "Running ({$cpus} vCPUs, {$mem}MB RAM, {$disk}GB Disk)" : "Stopped";

        $config = \OPNsense\Core\Config::getInstance()->object();
        $lanIp = (string)($config->interfaces->lan->ipaddr ?? '127.0.0.1');
        $sshEnabled = isset($config->system->ssh->enabled);

        return [
            'status' => $isRunning ? 'running' : 'stopped',
            'running' => $isRunning,
            'version' => $version,
            'microvm' => $microvmDesc,
            'ip' => '100.64.0.2',
            'subnet' => $subnet,
            'port_sync' => $portSync,
            'fail_on_conflict' => $conflictProt,
            'interfaces' => $interfaces,
            'lan_ip' => $lanIp,
            'ssh_enabled' => $sshEnabled
        ];
    }
}
