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

class ContainersController extends DockerApiControllerBase
{
    private const DF_CACHE_FILE = '/var/run/os-docker/df_cache.json';

    private function invalidateDfCache(): void
    {
        if (file_exists(self::DF_CACHE_FILE)) {
            @unlink(self::DF_CACHE_FILE);
        }
    }

    private function handleContainerAction($action, $id)
    {
        if (!$this->request->isPost()) {
            return ["status" => "failed", "message" => gettext("Method Not Allowed")];
        }

        $containerId = $id ?: $this->request->getPost('id');
        if (empty($containerId) || !$this->isValidIdentifier($containerId)) {
            return ["status" => "error", "message" => gettext("Valid container ID is required")];
        }

        $this->invalidateDfCache();

        if ($action === 'start') {
            return $this->executeRestAction("/containers/{$containerId}/start", 'POST', 'containers_start', $containerId);
        }
        if ($action === 'stop') {
            return $this->executeRestAction("/containers/{$containerId}/stop", 'POST', 'containers_stop', $containerId);
        }
        if ($action === 'restart') {
            return $this->executeRestAction("/containers/{$containerId}/restart", 'POST', 'containers_restart', $containerId);
        }
        if ($action === 'kill') {
            return $this->executeRestAction("/containers/{$containerId}/kill", 'POST', 'containers_kill', $containerId);
        }
        if ($action === 'delete') {
            return $this->executeRestAction("/containers/{$containerId}?v=1&force=1", 'DELETE', 'containers_delete', $containerId);
        }

        return $this->executeAction("containers_{$action}", $containerId);
    }

    public function listAction()
    {
        return $this->executeRestQuery('/containers/json?all=1', 'containers_list', function (array $containers) {
            $items = [];
            foreach ($containers as $c) {
                $rawNames = $c['Names'] ?? [];
                $names = array_map(function ($n) {
                    return ltrim($n, '/');
                }, $rawNames);

                $rawId = $c['Id'] ?? '';
                $items[] = [
                    'Id' => $rawId,
                    'ID' => substr($rawId, 0, 12),
                    'Names' => $names,
                    'Image' => $c['Image'] ?? '',
                    'ImageID' => $c['ImageID'] ?? '',
                    'State' => $c['State'] ?? '',
                    'Status' => $c['Status'] ?? '',
                    'Created' => $c['Created'] ?? 0,
                    'CreatedAt' => $c['Created'] ?? 0,
                    'Ports' => $c['Ports'] ?? [],
                    'Mounts' => $c['Mounts'] ?? []
                ];
            }
            return $items;
        });
    }

    public function startAction($id = null)
    {
        return $this->handleContainerAction('start', $id);
    }

    public function stopAction($id = null)
    {
        return $this->handleContainerAction('stop', $id);
    }

    public function killAction($id = null)
    {
        return $this->handleContainerAction('kill', $id);
    }

    public function restartAction($id = null)
    {
        return $this->handleContainerAction('restart', $id);
    }

    public function deleteAction($id = null)
    {
        return $this->handleContainerAction('delete', $id);
    }

    public function logsAction($id = null)
    {
        $containerId = $id ?: $this->request->get('id');
        if (empty($containerId) || !$this->isValidIdentifier($containerId)) {
            return ["status" => "error", "message" => gettext("Valid container ID is required")];
        }

        $res = $this->dockerRest("/containers/{$containerId}/logs?stdout=1&stderr=1&tail=200", 'GET', null, 3);
        if ($res['code'] >= 200 && $res['code'] < 300) {
            return ["status" => "ok", "output" => $this->stripDockerLogHeaders($res['body'])];
        }

        return $this->executeAction('containers_logs', $containerId);
    }

    public function inspectAction($id = null)
    {
        $containerId = $id ?: $this->request->get('id');
        if (empty($containerId) || !$this->isValidIdentifier($containerId)) {
            return ["status" => "error", "message" => gettext("Valid container ID is required")];
        }

        $res = $this->dockerRest("/containers/{$containerId}/json", 'GET', null, 2);
        if ($res['code'] >= 200 && $res['code'] < 300) {
            $data = json_decode($res['body'], true);
            $formatted = ($data !== null) ? json_encode($data, JSON_PRETTY_PRINT) : $res['body'];
            return ["status" => "ok", "output" => $formatted];
        }

        return $this->executeAction('containers_inspect', $containerId);
    }
}
