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

class VolumesController extends DockerApiControllerBase
{
    private const DF_CACHE_FILE = '/var/run/os-docker/df_cache.json';

    private function invalidateDfCache(): void
    {
        if (file_exists(self::DF_CACHE_FILE)) {
            @unlink(self::DF_CACHE_FILE);
        }
    }

    public function listAction()
    {
        return $this->executeRestQuery('/volumes', 'volumes_list', function (array $data) {
            $items = [];
            foreach ($data['Volumes'] ?? [] as $v) {
                $items[] = [
                    'Name' => $v['Name'] ?? '',
                    'Driver' => $v['Driver'] ?? 'local',
                    'Mountpoint' => $v['Mountpoint'] ?? '',
                    'CreatedAt' => $v['CreatedAt'] ?? '',
                    'Created' => $v['CreatedAt'] ?? ''
                ];
            }
            return $items;
        });
    }

    public function createAction()
    {
        if ($this->request->isPost()) {
            $name = $this->request->getPost('name');
            if (empty($name) || !$this->isValidIdentifier($name)) {
                return ["status" => "error", "message" => gettext("Valid volume name is required")];
            }
            $this->invalidateDfCache();
            return $this->executeRestAction('/volumes/create', 'POST', 'volumes_create', $name, json_encode(['Name' => $name]));
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }

    public function inspectAction($name = null)
    {
        $volumeName = $name ?: $this->request->get('name');
        if (empty($volumeName) || !$this->isValidIdentifier($volumeName)) {
            return ["status" => "error", "message" => gettext("Valid volume name is required")];
        }

        $res = $this->dockerRest("/volumes/{$volumeName}", 'GET', null, 2);
        if ($res['code'] >= 200 && $res['code'] < 300) {
            $data = json_decode($res['body'], true);
            $formatted = ($data !== null) ? json_encode($data, JSON_PRETTY_PRINT) : $res['body'];
            return ["status" => "ok", "output" => $formatted];
        }

        return $this->executeAction('volumes_inspect', $volumeName);
    }

    public function deleteAction($name = null)
    {
        if ($this->request->isPost()) {
            $volumeName = $name ?: $this->request->getPost('name');
            if (empty($volumeName) || !$this->isValidIdentifier($volumeName)) {
                return ["status" => "error", "message" => gettext("Valid volume name is required")];
            }
            $this->invalidateDfCache();
            return $this->executeRestAction("/volumes/{$volumeName}?force=1", 'DELETE', 'volumes_delete', $volumeName);
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }

    public function pruneAction()
    {
        if ($this->request->isPost()) {
            $this->invalidateDfCache();
            return $this->executeRestAction('/volumes/prune', 'POST', 'volumes_prune');
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }
}
