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

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

abstract class DockerApiControllerBase extends ApiControllerBase
{
    protected const DOCKER_REST_BASE = 'http://100.64.0.2:2375';
    protected const REST_TIMEOUT_SEC = 2;
    protected const REST_CONNECT_TIMEOUT_MS = 500;
    protected const STATUS_FILE = '/var/db/os-docker/manage_status.json';
    protected const DF_CACHE_FILE = '/var/run/os-docker/df_cache.json';

    protected function invalidateDfCache(): void
    {
        if (file_exists(self::DF_CACHE_FILE)) {
            @unlink(self::DF_CACHE_FILE);
        }
    }

    protected function executeAction($cmd, $param = null)
    {
        $backend = new Backend();
        if ($param !== null) {
            $params = is_array($param) ? $param : [$param];
            $response = $backend->configdpRun("docker {$cmd}", $params);
        } else {
            $response = $backend->configdRun("docker {$cmd}");
        }

        $result = json_decode($response, true);
        if ($result === null) {
            if (file_exists(self::STATUS_FILE)) {
                $fileData = json_decode(file_get_contents(self::STATUS_FILE), true);
                if ($fileData !== null) {
                    return $fileData;
                }
            }
            return ["status" => "error", "message" => $response ?: "Empty response from configd"];
        }
        return $result;
    }

    protected function dockerRest(string $endpoint, string $method = 'GET', ?string $data = null, int $timeout = self::REST_TIMEOUT_SEC): array
    {
        $url = self::DOCKER_REST_BASE . $endpoint;
        $ch = curl_init($url);

        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT_MS, self::REST_CONNECT_TIMEOUT_MS);
        curl_setopt($ch, CURLOPT_TIMEOUT, $timeout);

        if ($data !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
            curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        }

        $body = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err = curl_error($ch);
        curl_close($ch);

        return ['code' => (int)$code, 'body' => $body ?: '', 'error' => $err];
    }

    protected function executeRestQuery(string $endpoint, string $fallbackCmd, ?callable $transform = null): array
    {
        $res = $this->dockerRest($endpoint, 'GET', null, self::REST_TIMEOUT_SEC);
        $isSuccess = ($res['code'] === 304 || ($res['code'] >= 200 && $res['code'] < 300));
        if ($isSuccess) {
            $decoded = json_decode($res['body'], true);
            if ($decoded !== null) {
                if ($transform !== null) {
                    $decoded = $transform($decoded);
                }
                return ['status' => 'ok', 'items' => $decoded];
            }
        }

        return $this->executeAction($fallbackCmd);
    }

    protected function executeRestAction(string $endpoint, string $method, string $fallbackCmd, $fallbackParam = null, ?string $body = null): array
    {
        $res = $this->dockerRest($endpoint, $method, $body, 3);
        $isSuccess = ($res['code'] === 304 || ($res['code'] >= 200 && $res['code'] < 300));
        if ($isSuccess) {
            return ['status' => 'ok', 'output' => $res['body'] ?: 'OK'];
        }

        return $this->executeAction($fallbackCmd, $fallbackParam);
    }

    protected function stripDockerLogHeaders(string $raw): string
    {
        $out = '';
        $len = strlen($raw);
        $offset = 0;

        while ($offset < $len) {
            if ($offset + 8 > $len) {
                $out .= substr($raw, $offset);
                break;
            }

            $header = substr($raw, $offset, 8);
            $streamType = ord($header[0]);
            $isStreamHeader = ($streamType >= 0 && $streamType <= 2 && ord($header[1]) === 0 && ord($header[2]) === 0 && ord($header[3]) === 0);

            if ($isStreamHeader) {
                $frameSize = (ord($header[4]) << 24) | (ord($header[5]) << 16) | (ord($header[6]) << 8) | ord($header[7]);
                $offset += 8;
                if ($offset + $frameSize <= $len) {
                    $out .= substr($raw, $offset, $frameSize);
                    $offset += $frameSize;
                } else {
                    $out .= substr($raw, $offset);
                    break;
                }
            } else {
                $out .= substr($raw, $offset);
                break;
            }
        }

        return $out;
    }

    protected function formatBytes(int $bytes, int $precision = 1): string
    {
        if ($bytes <= 0) {
            return '0B';
        }

        $units = ['B', 'KB', 'MB', 'GB', 'TB'];
        $pow = min((int)floor(log($bytes, 1024)), count($units) - 1);
        $value = $bytes / pow(1024, $pow);

        return round($value, $precision) . $units[$pow];
    }

    protected function isValidIdentifier($val)
    {
        return is_string($val) && preg_match('/^[a-zA-Z0-9][a-zA-Z0-9_.:\/-]*$/', $val) === 1;
    }
}
