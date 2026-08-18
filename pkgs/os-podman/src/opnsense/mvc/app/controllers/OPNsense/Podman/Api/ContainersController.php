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

class ContainersController extends PodmanApiControllerBase
{
    private function handleContainerAction($action, $id)
    {
        if ($this->request->isPost()) {
            $containerId = $id ?: $this->request->getPost('id');
            if (empty($containerId)) {
                return ["status" => "error", "message" => "Container ID is required"];
            }
            return $this->executeAction("containers_{$action}", $containerId);
        }
        return ["status" => "failed"];
    }

    public function listAction()
    {
        return $this->executeAction('containers_list');
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
        if (empty($containerId)) {
            return ["status" => "error", "message" => "Container ID is required"];
        }
        return $this->executeAction('containers_logs', $containerId);
    }

    public function inspectAction($id = null)
    {
        $containerId = $id ?: $this->request->get('id');
        if (empty($containerId)) {
            return ["status" => "error", "message" => "Container ID is required"];
        }
        return $this->executeAction('containers_inspect', $containerId);
    }
}
