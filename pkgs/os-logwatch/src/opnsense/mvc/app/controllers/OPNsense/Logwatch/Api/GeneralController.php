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

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelClass = '\OPNsense\Logwatch\Logwatch';
    protected static $internalModelName = 'logwatch';
    protected static $internalModelPath = 'general';

    public function testSmtpAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'error', 'message' => gettext('Method Not Allowed')];
        }

        $payload = [];
        $useMonit = $this->request->getPost('use_monit_smtp');
        if ($useMonit !== null) {
            $payload['use_monit_smtp'] = ($useMonit === '1' || $useMonit === true || $useMonit === 'true');
            $payload['smtp_host'] = (string)$this->request->getPost('smtp_host', 'string', '');
            $payload['smtp_port'] = (int)$this->request->getPost('smtp_port', 'int', 587);
            $payload['smtp_user'] = (string)$this->request->getPost('smtp_user', 'string', '');
            $payload['smtp_password'] = (string)$this->request->getPost('smtp_password', 'string', '');
            $payload['smtp_from'] = (string)$this->request->getPost('smtp_from', 'string', '');
            $payload['smtp_to'] = (string)$this->request->getPost('smtp_to', 'string', '');
        }

        $b64 = base64_encode(json_encode($payload));
        $backend = new Backend();
        $raw = trim((string)$backend->configdpRun('logwatch test-smtp', [$b64]));
        if ($raw !== '' && strpos($raw, 'Execute error') === false) {
            $data = json_decode($raw, true);
            if (is_array($data)) {
                return $data;
            }
        }

        $statusFile = '/var/db/os-logwatch/manage_status.json';
        if (is_file($statusFile)) {
            $fileData = json_decode((string)file_get_contents($statusFile), true);
            if (is_array($fileData)) {
                return $fileData;
            }
        }

        return ['status' => 'error', 'message' => $raw !== '' ? $raw : gettext('Failed to send test email')];
    }
}
