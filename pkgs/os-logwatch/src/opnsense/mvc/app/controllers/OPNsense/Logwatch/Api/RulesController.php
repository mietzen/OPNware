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

use OPNsense\Core\Backend;
use OPNsense\Core\Config;
use OPNsense\Logwatch\Logwatch;

class RulesController extends LogwatchApiControllerBase
{
    public function getAction()
    {
        $mdl = new Logwatch();
        $yaml = $mdl->getRulesYaml();

        if (!$this->stageRulesText($yaml)) {
            return ['status' => 'error', 'message' => gettext('Cannot stage rules for parsing')];
        }

        $res = $this->runAction('rules-validate');
        if (($res['status'] ?? '') !== 'ok') {
            return ['status' => 'ok', 'yaml' => $yaml, 'parsed' => null, 'warning' => $res['message'] ?? ''];
        }

        return ['status' => 'ok', 'yaml' => $res['yaml'], 'parsed' => $res['parsed']];
    }

    public function saveAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'error', 'message' => gettext('Method Not Allowed')];
        }

        $rawYaml = $this->request->getPost('yaml');
        $parsedJson = $this->request->getPost('parsed');

        if (is_string($parsedJson) && $parsedJson !== '') {
            $stagedText = $parsedJson;
        } elseif (is_array($parsedJson)) {
            $stagedText = json_encode($parsedJson);
        } elseif (is_string($rawYaml)) {
            $stagedText = $rawYaml;
        } else {
            return ['status' => 'error', 'message' => gettext('Missing rules payload')];
        }

        if (!$this->stageRulesText($stagedText)) {
            return ['status' => 'error', 'message' => gettext('Cannot stage rules content')];
        }

        $res = $this->runAction('rules-validate');
        if (($res['status'] ?? '') !== 'ok') {
            return $res;
        }

        $mdl = new Logwatch();
        $mdl->rules->yaml_content = $res['yaml'];
        $mdl->serializeToConfig();
        Config::getInstance()->save();

        (new Backend())->configdRun('logwatch reload');
        return [
            'status' => 'ok',
            'message' => gettext('Rules validated, saved, and applied'),
            'yaml' => $res['yaml'],
            'parsed' => $res['parsed'],
        ];
    }

    public function alertStateAction()
    {
        return $this->runAction('alert-state');
    }

    public function resetCooldownAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'error', 'message' => gettext('Method Not Allowed')];
        }

        $payload = [
            'rule_name' => trim((string)$this->request->getPost('rule_name', 'string', '')),
            'clear_digest' => ((string)$this->request->getPost('clear_digest', 'string', '0') === '1' || $this->request->getPost('clear_digest') === true),
        ];

        return $this->runAction('reset-cooldown', base64_encode(json_encode($payload)));
    }
}
