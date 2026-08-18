#!/usr/local/bin/php
<?php

/*
 * OPNware os-homer — validated atomic save for /usr/local/www/homer/config.yml.
 *
 * Invoked via the configd `homer config-save` action (script_output) after the
 * config API controller stages the submitted content to the fixed staging
 * path. Direct CLI runs may pass the staged path as argv[1]. The content is
 * YAML-parsed and validated BEFORE anything is written; invalid YAML is
 * rejected and the file is left untouched. On success the file is applied
 * atomically (temp + rename in the target directory, mode 0644), creating
 * /usr/local/www/homer when it is missing. No service reload happens: Homer
 * re-reads config.yml in the browser on every page load.
 *
 * The result is echoed as JSON on stdout, e.g.
 *   {"status":"ok","message":"saved","parser":"symfony"}
 * and the exit code is 0 on success, 1 on failure. The same JSON is
 * persisted to the status file first, so the API controller can fall back
 * to it when configd swallows the script output on a non-zero exit
 * ("Execute error").
 *
 * YAML parser selection:
 *   1. Symfony\Component\Yaml\Yaml when available (preferred — OPNsense core
 *      ships it). Full YAML 1.2 semantics plus a precise parse error.
 *   2. The php yaml extension (yaml_parse, libyaml) when available. Full
 *      YAML 1.1 parse; !php/object nodes are disabled for safety.
 *   3. OPNsense's Python with PyYAML (yaml.safe_load) when available. Full
 *      YAML semantics; a non-zero return is an authoritative fail.
 *
 * The framework bootstrap (config.inc) is loaded only to make the Symfony
 * class_exists() check work when OPNsense core provides it.
 */

require_once 'config.inc';

const CONFIG_FILE = '/usr/local/www/homer/config.yml';
const STAGING_FILE = '/var/db/os-homer/config_staging/config.yml';
const STATUS_FILE = '/var/db/os-homer/config_status.json';

/**
 * Emit the JSON result and exit.
 */
function config_out($status, $message, $parser)
{
    $result = array(
        'status' => $status,
        'message' => $message,
        'parser' => $parser,
    );
    // Persist the outcome first: configd reports "Execute error" on non-zero
    // exits and drops the script output, so the controller falls back to
    // this file for the real message.
    $statusDir = dirname(STATUS_FILE);
    if (!is_dir($statusDir)) {
        @mkdir($statusDir, 0755, true);
    }
    @file_put_contents(STATUS_FILE, json_encode($result));
    echo json_encode($result);
    exit($status === 'ok' ? 0 : 1);
}

/**
 * Validate YAML content. Returns
 *   array('parser' => string, 'message' => string)
 * where message === '' means the content parsed cleanly, otherwise it carries
 * the parse error to surface inline in the WebUI.
 */
function config_validate($content)
{
    if (trim($content) === '') {
        return array('parser' => 'none', 'message' => '');
    }

    // 1. OPNsense core's Symfony YAML.
    if (class_exists('Symfony\\Component\\Yaml\\Yaml')) {
        try {
            Symfony\Component\Yaml\Yaml::parse($content);
            return array('parser' => 'symfony', 'message' => '');
        } catch (Exception $e) {
            return array(
                'parser' => 'symfony',
                'message' => 'YAML parse error: ' . $e->getMessage(),
            );
        }
    }

    // 2. The php yaml extension (libyaml).
    if (function_exists('yaml_parse')) {
        @ini_set('yaml.decode_php', 0); // never unserialize !php/object nodes
        $last = null;
        set_error_handler(function ($errno, $errstr) use (&$last) {
            $last = $errstr;
            return true;
        });
        $parsed = yaml_parse($content, -1);
        restore_error_handler();
        if ($parsed !== false) {
            return array('parser' => 'php-yaml', 'message' => '');
        }
        $detail = is_string($last) && trim($last) !== '' ? ' (' . trim($last) . ')' : '';
        return array(
            'parser' => 'php-yaml',
            'message' => 'YAML parse error' . $detail,
        );
    }

    // 3. OPNsense's Python with PyYAML (authoritative full parse when available).
    if (file_exists('/usr/local/bin/python3')) {
        $tmp = tempnam(sys_get_temp_dir(), 'homer-yaml');
        if ($tmp !== false) {
            @file_put_contents($tmp, $content);
            $cmd = "/usr/local/bin/python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1])); print(\"Valid YAML\")' " . escapeshellarg($tmp) . ' 2>&1';
            $out = array();
            $code = 0;
            exec($cmd, $out, $code);
            $stderr = trim(implode("\n", $out));
            @unlink($tmp);
            if ($code === 0) {
                return array('parser' => 'python-yaml', 'message' => '');
            }
            if (strpos($stderr, 'No module named') === false && $stderr !== '') {
                return array(
                    'parser' => 'python-yaml',
                    'message' => 'Error: invalid YAML',
                );
            }
        }
    }

    return array(
        'parser' => 'none',
        'message' => 'No YAML parser is available on this system.',
    );
}

// Read the staged content file. The configd action and the controller both
// use the fixed staging path; argv[1] is honored for direct CLI runs.
if ($argc >= 2) {
    $staged = $argv[1];
} else {
    $staged = STAGING_FILE;
}
$content = @file_get_contents($staged);
if ($content === false) {
    config_out('failure', 'cannot read staged content', 'none');
}

// Validate before writing anything; never write invalid YAML.
$validation = config_validate($content);
if ($validation['message'] !== '') {
    config_out('failure', $validation['message'], $validation['parser']);
}

// Ensure the target directory exists.
if (!is_dir(dirname(CONFIG_FILE)) && !mkdir(dirname(CONFIG_FILE), 0755, true)) {
    config_out('failure', 'cannot create ' . dirname(CONFIG_FILE), $validation['parser']);
}

// Atomic apply: temp file in the same directory, then rename() over the
// target. Never truncate the target in place.
$tmp = CONFIG_FILE . '.tmp';
if (file_put_contents($tmp, $content) === false) {
    @unlink($tmp);
    config_out('failure', 'cannot write ' . CONFIG_FILE, $validation['parser']);
}
chmod($tmp, 0644);
if (!rename($tmp, CONFIG_FILE)) {
    @unlink($tmp);
    config_out('failure', 'cannot write ' . CONFIG_FILE, $validation['parser']);
}
@unlink($staged);

config_out('ok', 'saved', $validation['parser']);
