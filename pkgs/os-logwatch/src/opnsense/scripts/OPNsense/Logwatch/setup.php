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

require_once('config.inc');

use OPNsense\Core\Config;
use OPNsense\Logwatch\Logwatch;

$stateDir = '/var/db/os-logwatch';
$seededFile = $stateDir . '/.seeded';

if (!is_dir($stateDir)) {
    @mkdir($stateDir, 0755, true);
}

// Seed default alert rules once on first install when yaml_content is empty.
if (!file_exists($seededFile)) {
    $mdl = new Logwatch();
    $currentYaml = trim((string)$mdl->rules->yaml_content);
    if ($currentYaml === '') {
        $mdl->rules->yaml_content = Logwatch::DEFAULT_RULES_YAML;
        $mdl->serializeToConfig();
        Config::getInstance()->save();
    }
    @touch($seededFile);
}

$extra = in_array('--no-reload', $argv ?? [], true) ? ' --no-reload' : '';
$cmd = '/usr/local/bin/python3 /usr/local/opnsense/scripts/OPNsense/Logwatch/manage.py setup' . $extra;
passthru($cmd, $rc);
exit($rc);
