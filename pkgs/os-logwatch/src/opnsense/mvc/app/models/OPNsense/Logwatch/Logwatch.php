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

use OPNsense\Base\BaseModel;

class Logwatch extends BaseModel
{
    public const DEFAULT_RULES_YAML = <<<'YAML'
alerts:
  - name: "Many warnings"
    count: 10
    window_minutes: 5
    level: warning
    above: false
  - name: "Any Error or above"
    count: 1
    window_minutes: 5
    level: err
    above: true
ignore: []
severity_rewrite: []
digest:
  enabled: false
  initial: 5m
  multiplier: 3
  max: 2h
  cooldown: 10m
YAML;

    /**
     * Return stored YAML rules or default starter rules when unconfigured.
     */
    public function getRulesYaml(): string
    {
        $raw = trim((string)$this->rules->yaml_content);
        if ($raw === '') {
            return self::DEFAULT_RULES_YAML . "\n";
        }
        return $raw . "\n";
    }
}
