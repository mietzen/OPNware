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

class LogsController extends LogwatchApiControllerBase
{
    private function readParam(string $name, $default = '')
    {
        if ($this->request->isPost()) {
            $val = $this->request->getPost($name);
            return ($val !== null) ? $val : $default;
        }
        $val = $this->request->get($name);
        return ($val !== null) ? $val : $default;
    }

    public function queryAction()
    {
        $params = [
            'host' => trim((string)$this->readParam('host', '')),
            'facility' => trim((string)$this->readParam('facility', '')),
            'severity' => trim((string)$this->readParam('severity', '')),
            'tag' => trim((string)$this->readParam('tag', '')),
            'search' => (string)$this->readParam('search', ''),
            'regex' => ((string)$this->readParam('regex', '0') === '1' || $this->readParam('regex') === true),
            'since' => (int)$this->readParam('since', 0),
            'until' => (int)$this->readParam('until', 0),
            'limit' => (int)$this->readParam('limit', 200),
            'offset' => (int)$this->readParam('offset', 0),
        ];

        return $this->runAction('query', $params);
    }

    public function filtersAction()
    {
        $params = [
            'host' => trim((string)$this->readParam('host', '')),
            'facility' => trim((string)$this->readParam('facility', '')),
            'severity' => trim((string)$this->readParam('severity', '')),
            'tag' => trim((string)$this->readParam('tag', '')),
        ];

        return $this->runAction('filters', $params);
    }

    public function statsAction()
    {
        return $this->runAction('stats');
    }

    public function clearAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'error', 'message' => gettext('Method Not Allowed')];
        }

        return $this->runAction('clear-logs');
    }

    public function addIgnoreAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'error', 'message' => gettext('Method Not Allowed')];
        }

        $mdl = new Logwatch();
        $rule = [
            'host' => trim((string)$this->request->getPost('host', 'string', '')),
            'facility' => trim((string)$this->request->getPost('facility', 'string', '')),
            'level' => trim((string)$this->request->getPost('level', 'string', '')),
            'tag' => trim((string)$this->request->getPost('tag', 'string', '')),
            'message' => trim((string)$this->request->getPost('message', 'string', '')),
            'discard' => ((string)$this->request->getPost('discard', 'string', '0') === '1' || $this->request->getPost('discard') === true),
        ];

        $payload = [
            'yaml' => $mdl->getRulesYaml(),
            'rule' => $rule,
        ];
        $res = $this->runAction('add-ignore', $payload);
        if (($res['status'] ?? '') !== 'ok') {
            return $res;
        }

        // Never persist an empty rules payload — a missing "yaml" key here is a
        // stale/invalid configd response and would wipe yaml_content on save.
        if (!isset($res['yaml']) || !is_string($res['yaml']) || trim($res['yaml']) === '') {
            return [
                'status' => 'error',
                'message' => gettext('Refusing to save empty rules (stale or invalid configd response)'),
            ];
        }

        $mdl->rules->yaml_content = $res['yaml'];
        $mdl->serializeToConfig();
        Config::getInstance()->save();

        (new Backend())->configdRun('logwatch reload');
        return ['status' => 'ok', 'message' => gettext('Ignore rule saved and applied'), 'parsed' => $res['parsed']];
    }
}
