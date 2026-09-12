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

class ImagesController extends DockerApiControllerBase
{
    public function listAction()
    {
        return $this->executeRestQuery('/images/json', 'images_list', function (array $images) {
            $items = [];
            foreach ($images as $img) {
                $rawTags = $img['RepoTags'] ?? [];
                $names = !empty($rawTags) ? $rawTags : ['<none>'];
                $rawId = str_replace('sha256:', '', $img['Id'] ?? '');

                $items[] = [
                    'Id' => $rawId,
                    'ID' => substr($rawId, 0, 12),
                    'Names' => $names,
                    'Repository' => $names[0] ?? '<none>',
                    'Size' => $img['Size'] ?? 0,
                    'Created' => $img['Created'] ?? 0,
                    'CreatedAt' => $img['Created'] ?? 0
                ];
            }
            return $items;
        });
    }

    public function pullAction()
    {
        if ($this->request->isPost()) {
            $image = $this->request->getPost('image');
            if (empty($image) || !$this->isValidIdentifier($image)) {
                return ["status" => "error", "message" => gettext("Valid image reference is required")];
            }
            $this->invalidateDfCache();
            return $this->executeAction('images_pull', $image);
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }

    public function deleteAction($id = null)
    {
        if ($this->request->isPost()) {
            $imageId = $id ?: $this->request->getPost('id');
            if (empty($imageId) || !$this->isValidIdentifier($imageId)) {
                return ["status" => "error", "message" => gettext("Valid image ID is required")];
            }
            $this->invalidateDfCache();
            return $this->executeRestAction("/images/{$imageId}?force=1", 'DELETE', 'images_delete', $imageId);
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }

    public function pruneAction()
    {
        if ($this->request->isPost()) {
            $this->invalidateDfCache();
            return $this->executeRestAction('/images/prune', 'POST', 'images_prune');
        }
        return ["status" => "failed", "message" => gettext("Method Not Allowed")];
    }
}
