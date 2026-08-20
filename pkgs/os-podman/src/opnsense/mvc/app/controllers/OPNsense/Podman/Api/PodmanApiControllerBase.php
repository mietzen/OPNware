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

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

abstract class PodmanApiControllerBase extends ApiControllerBase
{
    protected function executeAction($cmd, $param = null)
    {
        $backend = new Backend();
        if ($param !== null) {
            $params = is_array($param) ? $param : [$param];
            $response = $backend->configdpRun("podman {$cmd}", $params);
        } else {
            $response = $backend->configdRun("podman {$cmd}");
        }

        $result = json_decode($response, true);
        if ($result === null) {
            $statusFile = '/var/db/podman/manage_status.json';
            if (file_exists($statusFile)) {
                $fileData = json_decode(file_get_contents($statusFile), true);
                if ($fileData !== null) {
                    return $fileData;
                }
            }
            return ["status" => "error", "message" => $response ?: "Empty response from configd"];
        }
        return $result;
    }

    protected function isValidIdentifier($val)
    {
        return is_string($val) && preg_match('/^[a-zA-Z0-9][a-zA-Z0-9_.:\/-]*$/', $val) === 1;
    }
}
