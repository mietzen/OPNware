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

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Logwatch\Logwatch';
    protected static $internalServiceTemplate = 'OPNsense/Logwatch';
    protected static $internalServiceEnabled = 'general.enabled';
    protected static $internalServiceName = 'logwatch';

    public function statusAction()
    {
        $backend = new Backend();
        $response = $backend->configdRun('logwatch status');
        $status = (strpos((string)$response, 'is running') !== false) ? 'running' : 'stopped';

        return [
            'status' => $status,
            'widget' => [
                'caption_restart' => gettext('Restart'),
                'caption_start' => gettext('Start'),
                'caption_stop' => gettext('Stop'),
            ],
        ];
    }

    public function reconfigureAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failure', 'message' => gettext('Method Not Allowed')];
        }

        $backend = new Backend();
        $tmpl = trim((string)$backend->configdRun('template reload OPNsense/Logwatch'));
        if ($tmpl !== 'OK') {
            return ['status' => 'failure', 'message' => $tmpl];
        }

        if ($this->serviceEnabled()) {
            // Start daemon before enabling syslog-ng destination so ingest.sock is already bound
            if ($this->statusAction()['status'] !== 'running') {
                $backend->configdRun('logwatch start');
            } else {
                $backend->configdRun('logwatch reload');
            }

            $setupRes = json_decode((string)$backend->configdRun('logwatch setup'), true);
            if (is_array($setupRes) && ($setupRes['status'] ?? '') === 'error') {
                return ['status' => 'failure', 'message' => $setupRes['message'] ?? 'Setup failed'];
            }
        } else {
            // Disable syslog-ng destination before stopping daemon to avoid socket errors
            $backend->configdRun('logwatch setup');
            $backend->configdRun('logwatch stop');
        }

        $backend->configdRun('filter reload');
        return ['status' => 'ok'];
    }
}
