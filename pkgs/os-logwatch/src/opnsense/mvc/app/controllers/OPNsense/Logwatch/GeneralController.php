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

namespace OPNsense\Logwatch;

use OPNsense\Base\IndexController;
use OPNsense\Core\Config;

class GeneralController extends IndexController
{
    public function indexAction()
    {
        $this->view->generalForm = $this->getForm('general');
        $this->view->monitSummary = $this->readMonitSummary();
        $this->view->pick('OPNsense/Logwatch/general');
    }

    private function readMonitSummary(): array
    {
        $config = Config::getInstance()->object();
        $monit = $config->OPNsense->monit ?? null;
        if ($monit === null || !isset($monit->general)) {
            return ['configured' => false];
        }

        $host = trim((string)($monit->general->mailserver ?? ''));
        $port = trim((string)($monit->general->port ?? '587'));
        $to = '';

        if (isset($monit->alert)) {
            foreach ($monit->alert as $alert) {
                if ((string)($alert->enabled ?? '0') !== '1') {
                    continue;
                }
                $recip = trim((string)($alert->recipient ?? ''));
                if ($recip !== '' && $recip !== 'root@localhost.local') {
                    $to = $recip;
                    break;
                }
            }
        }

        return [
            'configured' => ($host !== '' && $host !== '127.0.0.1'),
            'host' => $host,
            'port' => $port,
            'to' => $to,
        ];
    }
}
