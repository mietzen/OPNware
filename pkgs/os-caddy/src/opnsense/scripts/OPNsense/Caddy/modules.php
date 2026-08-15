<?php

/*
 * OPNware os-caddy — xcaddy-pinned module management with self-healing ensure.
 *
 * Modes (first CLI arg):
 *   rebuild — build a new caddy binary from the declared module set, pinned
 *             to the installed caddy version, verify the result, then swap
 *             it over /usr/local/bin/caddy atomically. A failed build or
 *             verification never touches the installed binary.
 *   ensure  — compare the stored build fingerprint and the declared module
 *             set against the installed binary; rebuild only when they
 *             mismatch (e.g. after a caddy package update).
 *
 * Results are written to /var/db/os-caddy/modules_result.json and echoed as
 * JSON on stdout (configd script_output actions capture stdout).
 */

use OPNsense\Core\Config;

require_once 'config.inc';

const CADDY_BIN = '/usr/local/bin/caddy';
const XCADDY_BIN = '/usr/local/bin/xcaddy';
const STATE_DIR = '/var/db/os-caddy';
const RUN_DIR = '/var/run/os-caddy';
const TEMP_BIN = '/tmp/opnware-caddy.new';
const RESULT_FILE = STATE_DIR . '/modules_result.json';
const FINGERPRINT_FILE = STATE_DIR . '/build.fingerprint';

/**
 * Write the failure result and exit non-zero. Never leaves a partial binary.
 */
function fail($message, $output = '')
{
    $result = array(
        'ok' => false,
        'message' => $message,
        'ts' => time(),
    );
    if ($output !== '') {
        $result['output'] = $output;
    }
    file_put_contents(RESULT_FILE, json_encode($result));
    echo json_encode($result);
    exit(1);
}

/**
 * Run a command, capturing combined output.
 */
function run_cmd($cmd, &$out, &$code)
{
    $out = array();
    exec($cmd . ' 2>&1', $out, $code);
    return $code;
}

/**
 * Declared module set from the OPNsense config (general.Modules, one per line).
 */
function declared_modules()
{
    $config = Config::getInstance()->object();
    $modules = array();
    if (isset($config->OPNsense->caddy->general->Modules)) {
        $modules = explode("\n", (string)$config->OPNsense->caddy->general->Modules);
    }
    $seen = array();
    $result = array();
    foreach ($modules as $module) {
        $module = trim($module);
        if ($module !== '' && !isset($seen[$module])) {
            $seen[$module] = true;
            $result[] = $module;
        }
    }
    return $result;
}

/**
 * Installed caddy version, e.g. "v2.11.4 h1:..." -> "2.11.4".
 */
function installed_version()
{
    run_cmd(CADDY_BIN . ' version', $out, $code);
    if ($code !== 0 || empty($out)) {
        fail('cannot determine installed caddy version', implode("\n", $out));
    }
    $line = trim($out[0]);
    $tokens = explode(' ', $line);
    $version = ltrim($tokens[0], 'v');
    if ($version === '') {
        fail('cannot parse caddy version from: ' . $line);
    }
    return $version;
}

/**
 * Go package paths of the non-standard modules in the given binary.
 * `caddy list-modules --packages --skip-standard` prints "<moduleID> <packagePath>"
 * per line, followed by a "Non-standard modules: N" summary line.
 */
function list_module_packages($binary)
{
    run_cmd(escapeshellarg($binary) . ' list-modules --packages --skip-standard', $out, $code);
    if ($code !== 0) {
        fail('cannot list modules of ' . $binary, implode("\n", $out));
    }
    $packages = array();
    foreach ($out as $line) {
        $line = trim($line);
        if ($line === '' || preg_match('/^(Standard|Non-standard|Unknown) modules:/', $line)) {
            continue;
        }
        $parts = preg_split('/\s+/', $line);
        if (count($parts) >= 2) {
            $packages[] = $parts[1];
        }
    }
    return $packages;
}

/**
 * Verify a freshly built binary before it may replace the installed one:
 * it must run, report the pinned version and contain every declared module.
 */
function verify_binary($binary, $modules, $version)
{
    run_cmd(escapeshellarg($binary) . ' version', $out, $code);
    if ($code !== 0 || empty($out)) {
        fail('new binary does not run', implode("\n", $out));
    }
    $tokens = explode(' ', trim($out[0]));
    $new_version = ltrim($tokens[0], 'v');
    if ($new_version !== $version) {
        fail("new binary version mismatch: expected $version, got $new_version");
    }

    $packages = list_module_packages($binary);
    foreach ($modules as $module) {
        if (!in_array($module, $packages, true)) {
            fail("declared module not present in new binary: $module");
        }
    }
}

/**
 * Rebuild the caddy binary pinned to the installed version, verify it and
 * swap it over /usr/local/bin/caddy atomically.
 */
function rebuild($modules)
{
    $version = installed_version();

    foreach (array(STATE_DIR, RUN_DIR, STATE_DIR . '/gocache') as $dir) {
        if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
            fail("cannot create $dir");
        }
        chmod($dir, 0755);
    }

    if (file_exists(TEMP_BIN)) {
        unlink(TEMP_BIN);
    }

    $cmd = '/usr/bin/env PATH=/usr/local/bin:/usr/bin:/bin '
        . 'GOCACHE=' . escapeshellarg(STATE_DIR . '/gocache') . ' '
        . 'HOME=' . escapeshellarg(STATE_DIR) . ' '
        . XCADDY_BIN . ' build ' . escapeshellarg('v' . $version)
        . ' --output ' . escapeshellarg(TEMP_BIN);
    foreach ($modules as $module) {
        $cmd .= ' --with ' . escapeshellarg($module);
    }

    run_cmd($cmd, $out, $code);
    if ($code !== 0 || !is_file(TEMP_BIN)) {
        if (file_exists(TEMP_BIN)) {
            unlink(TEMP_BIN);
        }
        fail('xcaddy build failed', implode("\n", $out));
    }

    // verify before touching the installed binary
    verify_binary(TEMP_BIN, $modules, $version);

    // atomic swap (same filesystem); the old binary stays until this succeeds
    if (!rename(TEMP_BIN, CADDY_BIN)) {
        unlink(TEMP_BIN);
        fail('cannot swap new binary into place');
    }
    chmod(CADDY_BIN, 0755);

    $fingerprint = hash_file('sha256', CADDY_BIN);
    if ($fingerprint === false) {
        fail('cannot fingerprint installed binary');
    }
    file_put_contents(FINGERPRINT_FILE, $fingerprint . "\n");

    $result = array(
        'ok' => true,
        'version' => $version,
        'fingerprint' => $fingerprint,
        'ts' => time(),
    );
    file_put_contents(RESULT_FILE, json_encode($result));
    echo json_encode($result);
    exit(0);
}

/**
 * Self-healing check: rebuild only when the stored fingerprint no longer
 * matches the installed binary or a declared module is missing.
 */
function ensure($modules)
{
    $stored = '';
    if (is_file(FINGERPRINT_FILE)) {
        $stored = trim(file_get_contents(FINGERPRINT_FILE));
    }

    $current = '';
    if (is_file(CADDY_BIN)) {
        $current = hash_file('sha256', CADDY_BIN);
    }

    $up_to_date = $stored !== '' && $stored === $current;
    if ($up_to_date && !empty($modules)) {
        $packages = list_module_packages(CADDY_BIN);
        foreach ($modules as $module) {
            if (!in_array($module, $packages, true)) {
                $up_to_date = false;
                break;
            }
        }
    }

    if ($up_to_date) {
        $result = array(
            'ok' => true,
            'noop' => true,
            'version' => installed_version(),
            'fingerprint' => $current,
            'ts' => time(),
        );
        file_put_contents(RESULT_FILE, json_encode($result));
        echo json_encode($result);
        exit(0);
    }

    rebuild($modules);
}

$mode = isset($argv[1]) ? $argv[1] : '';
$modules = declared_modules();

switch ($mode) {
    case 'rebuild':
        rebuild($modules);
        break;
    case 'ensure':
        ensure($modules);
        break;
    default:
        echo json_encode(array(
            'ok' => false,
            'message' => 'usage: modules.php rebuild|ensure',
            'ts' => time(),
        ));
        exit(1);
}