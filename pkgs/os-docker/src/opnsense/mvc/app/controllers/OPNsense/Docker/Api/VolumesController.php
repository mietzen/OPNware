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
    public function listAction()
    {
        return $this->executeAction('volumes_list');
    }

    public function createAction()
    {
        if ($this->request->isPost()) {
            $name = $this->request->getPost('name');
            if (empty($name) || !$this->isValidIdentifier($name)) {
                return ["status" => "error", "message" => gettext("Valid volume name is required")];
            }
            return $this->executeAction('volumes_create', $name);
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }

    public function inspectAction($name = null)
    {
        $volumeName = $name ?: $this->request->get('name');
        if (empty($volumeName) || !$this->isValidIdentifier($volumeName)) {
            return ["status" => "error", "message" => gettext("Valid volume name is required")];
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
            return $this->executeAction('volumes_delete', $volumeName);
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }

    public function pruneAction()
    {
        if ($this->request->isPost()) {
            return $this->executeAction('volumes_prune');
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }
}
