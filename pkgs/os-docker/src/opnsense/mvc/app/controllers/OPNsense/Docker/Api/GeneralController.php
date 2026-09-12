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

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelClass = '\OPNsense\Docker\Docker';
    protected static $internalModelName = 'docker';
    protected static $internalModelPath = 'general';

    public function hostResourcesAction()
    {
        $backend = new Backend();
        $response = $backend->configdRun('docker host_resources');
        $data = json_decode($response, true);
        if ($data === null) {
            $data = [
                'cpus' => 2,
                'memory_mb' => 2048,
                'disk_free_gb' => 50,
            ];
        }
        return $data;
    }

    public function metricsAction()
    {
        $cacheFile = '/var/run/os-docker/metrics_cache.json';
        if (file_exists($cacheFile)) {
            $mtime = filemtime($cacheFile);
            if ($mtime !== false && (time() - $mtime) < 3) {
                $cached = json_decode((string)file_get_contents($cacheFile), true);
                if (is_array($cached)) {
                    return $cached;
                }
            }
        }

        $backend = new \OPNsense\Core\Backend();
        $response = $backend->configdRun('docker metrics');
        $res = json_decode($response, true);
        if (is_array($res) && isset($res['status'])) {
            @file_put_contents($cacheFile, json_encode($res));
            return $res;
        }

        $fallback = [
            'status' => 'ok',
            'running' => false,
            'cpu' => ['display' => '--', 'load_1m' => 0, 'percent' => 0, 'vcpus' => 2],
            'ram' => ['display' => '--', 'used_mb' => 0, 'total_mb' => 0, 'percent' => 0],
            'disk' => ['display' => '--', 'used_gb' => 0, 'total_gb' => 0, 'percent' => 0]
        ];
        @file_put_contents($cacheFile, json_encode($fallback));
        return $fallback;
    }
}
