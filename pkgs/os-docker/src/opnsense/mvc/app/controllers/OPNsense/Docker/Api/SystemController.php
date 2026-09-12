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
    private const DF_CACHE_FILE = '/var/run/os-docker/df_cache.json';
    private const DF_CACHE_TTL = 15;
    private const CONFLICTS_FILE = '/var/db/os-docker/conflicts.json';

    private function invalidateDfCache(): void
    {
        if (file_exists(self::DF_CACHE_FILE)) {
            @unlink(self::DF_CACHE_FILE);
        }
    }

    public function dfAction()
    {
        if (file_exists(self::DF_CACHE_FILE)) {
            $mtime = filemtime(self::DF_CACHE_FILE);
            if ($mtime !== false && (time() - $mtime) < self::DF_CACHE_TTL) {
                $cached = json_decode((string)file_get_contents(self::DF_CACHE_FILE), true);
                if (is_array($cached) && !empty($cached['items'])) {
                    return $cached;
                }
            }
        }

        $res = $this->dockerRest('/system/df', 'GET', null, 3);
        if ($res['code'] >= 200 && $res['code'] < 300) {
            $df = json_decode($res['body'], true);
            if (is_array($df)) {
                $containers = $df['Containers'] ?? [];
                $activeContainers = 0;
                foreach ($containers as $c) {
                    $state = strtolower($c['State'] ?? '');
                    $status = strtolower($c['Status'] ?? '');
                    if ($state === 'running' || strpos($status, 'up') !== false) {
                        $activeContainers++;
                    }
                }

                $images = $df['Images'] ?? [];
                $activeImages = 0;
                $totalImgSize = 0;
                $reclaimableImgSize = 0;
                foreach ($images as $img) {
                    $size = (int)($img['Size'] ?? 0);
                    $totalImgSize += $size;
                    $refContainers = (int)($img['Containers'] ?? 0);
                    if ($refContainers > 0) {
                        $activeImages++;
                    } else {
                        $reclaimableImgSize += $size;
                    }
                }

                $volumes = $df['Volumes'] ?? [];
                $activeVolumes = 0;
                $totalVolSize = 0;
                $reclaimableVolSize = 0;
                foreach ($volumes as $v) {
                    $usage = $v['UsageData'] ?? [];
                    $size = (int)($usage['Size'] ?? 0);
                    $totalVolSize += $size;
                    $refCount = (int)($usage['RefCount'] ?? 0);
                    if ($refCount > 0) {
                        $activeVolumes++;
                    } else {
                        $reclaimableVolSize += $size;
                    }
                }

                $items = [
                    [
                        'Type' => 'Images',
                        'Total' => count($images),
                        'TotalCount' => count($images),
                        'Active' => $activeImages,
                        'Size' => $this->formatBytes($totalImgSize),
                        'Reclaimable' => $this->formatBytes($reclaimableImgSize)
                    ],
                    [
                        'Type' => 'Containers',
                        'Total' => count($containers),
                        'TotalCount' => count($containers),
                        'Active' => $activeContainers
                    ],
                    [
                        'Type' => 'Local Volumes',
                        'Total' => count($volumes),
                        'TotalCount' => count($volumes),
                        'Active' => $activeVolumes,
                        'Size' => $this->formatBytes($totalVolSize),
                        'Reclaimable' => $this->formatBytes($reclaimableVolSize)
                    ]
                ];

                $response = ['status' => 'ok', 'items' => $items];
                @file_put_contents(self::DF_CACHE_FILE, json_encode($response));
                return $response;
            }
        }

        return $this->executeAction('system_df');
    }

    public function statsAction()
    {
        return $this->executeRestQuery('/containers/json', 'system_stats');
    }

    public function infoAction()
    {
        $res = $this->dockerRest('/info', 'GET', null, 2);
        if ($res['code'] >= 200 && $res['code'] < 300) {
            $data = json_decode($res['body'], true);
            if ($data !== null) {
                return ['status' => 'ok', 'items' => [$data]];
            }
        }
        return $this->executeAction('system_info');
    }

    public function pruneAction()
    {
        if ($this->request->isPost()) {
            $this->invalidateDfCache();
            return $this->executeRestAction('/system/prune?volumes=1', 'POST', 'system_prune');
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }

    public function conflictsAction()
    {
        if (file_exists(self::CONFLICTS_FILE)) {
            $data = json_decode((string)file_get_contents(self::CONFLICTS_FILE), true);
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
