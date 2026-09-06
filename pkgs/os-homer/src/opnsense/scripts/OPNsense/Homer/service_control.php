#!/usr/local/bin/php
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

require_once 'config.inc';
require_once 'plugins.inc.d/homer.inc';

use OPNsense\Core\Backend;

$action = $argv[1] ?? 'status';

if (homer_caddy_is_present()) {
    $backend = new Backend();
    if ($action === 'start' || $action === 'restart' || $action === 'reload') {
        $backend->configdRun('homer sync-caddy');
        $backend->configdRun('caddyadvanced restart');
    } elseif ($action === 'stop') {
        $homerCaddyFile = '/usr/local/etc/caddy/conf.d/homer.caddy';
        if (file_exists($homerCaddyFile)) {
            @unlink($homerCaddyFile);
            $backend->configdRun('caddyadvanced restart');
        }
        @shell_exec('/usr/sbin/service homer onestop >/dev/null 2>&1');
    }
    exit(0);
}

// Standalone Homer service
$cmd = match ($action) {
    'start' => '/usr/sbin/service homer start',
    'stop' => '/usr/sbin/service homer stop',
    'restart', 'reload' => '/usr/sbin/service homer restart',
    default => '/usr/sbin/service homer status',
};

passthru($cmd, $rc);
exit($rc);
