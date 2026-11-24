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

namespace OPNsense\Logwatch\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

abstract class LogwatchApiControllerBase extends ApiControllerBase
{
    protected const STATE_DIR = '/var/db/os-logwatch';
    protected const STATUS_FILE = '/var/db/os-logwatch/manage_status.json';
    protected const STAGED_RULES = '/var/db/os-logwatch/staged_rules.yml';

    /**
     * Atomically stage a JSON payload for a configd action into
     * /var/db/os-logwatch/request_<cmd>.json (mode 0600 — payloads may contain
     * secrets such as SMTP credentials and must never travel through configd
     * parameters, whose socket messages are truncated at 4KB and logged).
     * Embeds a random request_id nonce into the payload and returns it, so
     * runAction can verify the response belongs to this exact request.
     * Returns the request id on success, null on failure.
     */
    public static function stageRequest(string $cmd, array $payload): ?string
    {
        if (!preg_match('/^[a-z0-9-]+$/', $cmd)) {
            return null;
        }

        if (!is_dir(self::STATE_DIR) && !@mkdir(self::STATE_DIR, 0755, true)) {
            return null;
        }

        $requestId = bin2hex(random_bytes(8));
        $payload['request_id'] = $requestId;

        $path = self::STATE_DIR . '/request_' . $cmd . '.json';
        // Unique tmp name per call; umask(0077) makes the tmp file 0600 from
        // the moment of creation so the payload is never world-readable.
        $tmp = $path . '.' . getmypid() . '.tmp';
        $oldUmask = umask(0077);
        $written = file_put_contents($tmp, json_encode($payload)) !== false;
        umask($oldUmask);
        if (!$written) {
            @unlink($tmp);
            return null;
        }

        chmod($tmp, 0600);
        if (!rename($tmp, $path)) {
            @unlink($tmp);
            return null;
        }

        return $requestId;
    }

    /**
     * Execute a configd action under the logwatch namespace and decode JSON,
     * falling back to manage_status.json if configd swallowed output.
     * When a payload is given it is staged to request_<cmd>.json first and the
     * action is invoked WITHOUT parameters. The response (direct or from the
     * status file) is only accepted when it carries cmd === $cmd and, if a
     * payload was staged, request_id === the nonce stageRequest embedded —
     * anything else is a stale response from a previous command and is
     * rejected.
     */
    public static function runAction(string $cmd, $payload = null): array
    {
        $backend = new Backend();
        $requestId = null;
        if ($payload !== null) {
            if (!is_array($payload)) {
                return [
                    'status' => 'error',
                    'message' => gettext('Cannot stage request payload for configd'),
                ];
            }
            $requestId = self::stageRequest($cmd, $payload);
            if ($requestId === null) {
                return [
                    'status' => 'error',
                    'message' => gettext('Cannot stage request payload for configd'),
                ];
            }
        }

        $response = $backend->configdRun("logwatch {$cmd}");

        $result = json_decode((string)$response, true);
        if (!is_array($result) && is_file(self::STATUS_FILE)) {
            $fileData = json_decode((string)file_get_contents(self::STATUS_FILE), true);
            if (is_array($fileData)) {
                $result = $fileData;
            }
        }

        if (is_array($result) && ($result['cmd'] ?? null) === $cmd
            && ($requestId === null || ($result['request_id'] ?? null) === $requestId)) {
            return $result;
        }

        $detail = '';
        if (is_array($result) && isset($result['message'])
            && is_string($result['message']) && $result['message'] !== '') {
            $detail = ': ' . $result['message'];
        }

        return [
            'status' => 'error',
            'message' => is_array($result)
                ? gettext('stale or invalid configd response') . $detail
                : (trim((string)$response) ?: gettext('Empty response from configd')),
        ];
    }

    protected function stageRulesText(string $content): bool
    {
        if (!is_dir(self::STATE_DIR) && !@mkdir(self::STATE_DIR, 0755, true)) {
            return false;
        }

        $tmp = self::STAGED_RULES . '.tmp';
        if (file_put_contents($tmp, $content) === false) {
            return false;
        }

        if (!rename($tmp, self::STAGED_RULES)) {
            @unlink($tmp);
            return false;
        }

        return true;
    }
}
