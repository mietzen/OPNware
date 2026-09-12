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

class NetworksController extends DockerApiControllerBase
{
    public function listAction()
    {
        return $this->executeRestQuery('/networks', 'networks_list', function (array $networks) {
            $items = [];
            foreach ($networks as $net) {
                $subnets = [];
                if (!empty($net['IPAM']['Config'])) {
                    foreach ($net['IPAM']['Config'] as $cfg) {
                        if (!empty($cfg['Subnet'])) {
                            $subnets[] = ['Subnet' => $cfg['Subnet']];
                        }
                    }
                }

                $rawId = $net['Id'] ?? '';
                $items[] = [
                    'Id' => $rawId,
                    'ID' => substr($rawId, 0, 12),
                    'Name' => $net['Name'] ?? '',
                    'name' => $net['Name'] ?? '',
                    'Driver' => $net['Driver'] ?? 'bridge',
                    'Scope' => $net['Scope'] ?? 'local',
                    'Subnets' => $subnets
                ];
            }
            return $items;
        });
    }

    public function deleteAction($name = null)
    {
        if ($this->request->isPost()) {
            $netName = $name ?: $this->request->getPost('name');
            if (empty($netName) || !$this->isValidIdentifier($netName)) {
                return ["status" => "error", "message" => gettext("Valid network name is required")];
            }
            return $this->executeRestAction("/networks/{$netName}", 'DELETE', 'networks_delete', $netName);
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }

    public function inspectAction($name = null)
    {
        $netName = $name ?: $this->request->get('name');
        if (empty($netName) || !$this->isValidIdentifier($netName)) {
            return ["status" => "error", "message" => gettext("Valid network identifier is required")];
        }

        $res = $this->dockerRest("/networks/{$netName}", 'GET', null, 2);
        if ($res['code'] >= 200 && $res['code'] < 300) {
            $data = json_decode($res['body'], true);
            $formatted = ($data !== null) ? json_encode($data, JSON_PRETTY_PRINT) : $res['body'];
            return ["status" => "ok", "output" => $formatted];
        }

        return $this->executeAction('networks_inspect', $netName);
    }
}
