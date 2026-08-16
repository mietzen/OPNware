#!/usr/local/bin/php
<?php

/*
 * OPNware os-caddy — save cycle for the user-owned Caddy file tree.
 *
 * One configd action, serialized via flock on /var/run/os-caddy-advanced/editor.lock.
 * It reads the file set staged by the editor API (from
 * /var/db/os-caddy-advanced/editor_staging), validates the whole resulting tree
 * (Caddyfile + conf.d/*.caddy) with `caddy validate` against a temp copy,
 * snapshots the current files into /var/db/os-caddy-advanced/rollback/, applies the
 * staged files atomically (temp + rename, never truncate in place), then
 * reloads Caddy gracefully — skipped silently when the service is stopped.
 * On reload failure the snapshot is restored, the previous config reloaded
 * and the error plus a rollback notice is returned. The outcome is recorded
 * in /var/db/os-caddy-advanced/editor_status.json ({last_save, result, message}) and
 * echoed as JSON on stdout (configd script_output actions capture stdout).
 *
 * Only files of the flat tree (/usr/local/etc/caddy/Caddyfile and
 * /usr/local/etc/caddy/conf.d/*.caddy) are ever read or written; every path
 * is joined from the fixed base and must resolve back under it. The import
 * glob is non-recursive, so subdirectories are never touched.
 */

use OPNsense\Core\Config;

require_once 'config.inc';
require_once __DIR__ . '/editor_tree.php';

const CADDY_BIN = '/usr/local/bin/caddy';
const BASE = '/usr/local/etc/caddy';
const RUN_DIR = '/var/run/os-caddy-advanced';
const STATE_DIR = '/var/db/os-caddy-advanced';
const STAGING_DIR = STATE_DIR . '/editor_staging';
const ROLLBACK_DIR = STATE_DIR . '/rollback';
const LOCK_FILE = RUN_DIR . '/editor.lock';
const STATUS_FILE = STATE_DIR . '/editor_status.json';
const COMPLETE_STAGING_MARKER = STAGING_DIR . '/.complete';

/**
 * Run a command, capturing combined output.
 */
function editor_run_cmd($cmd, &$out, &$code)
{
    $out = array();
    exec($cmd . ' 2>&1', $out, $code);
    return $code;
}

/**
 * Safe relative path check: only "Caddyfile" or a single-component *.caddy
 * file directly inside "conf.d" is allowed. Rejects traversal (".."),
 * absolute paths and any nesting (the import glob is non-recursive).
 */
function editor_safe_rel($rel)
{
    if ($rel === 'Caddyfile') {
        return true;
    }
    return (bool)preg_match('#^conf\.d/[A-Za-z0-9._-]+\.caddy$#', $rel);
}

/**
 * Whether $path resolves to a real location strictly under $base. Used to
 * refuse symlink escapes when reading tree files.
 */
function editor_under_base($path, $base)
{
    $real = realpath($path);
    if ($real === false) {
        return false;
    }
    $real_base = realpath($base);
    if ($real_base === false) {
        return false;
    }
    return strpos($real, $real_base . '/') === 0;
}

/**
 * Whether a write to $target (under $base) is safe: the parent directory must
 * resolve to a real location under $base and must not be a symlink. This is
 * checked immediately before every write so a swapped/symlinked conf.d can
 * never redirect a rename() outside the tree.
 */
function editor_write_target_ok($target, $base)
{
    $dir = dirname($target);
    if (is_link($dir)) {
        return false;
    }
    $real = realpath($dir);
    if ($real === false) {
        if (!mkdir($dir, 0755, true)) {
            return false;
        }
        $real = realpath($dir);
        if ($real === false) {
            return false;
        }
    }
    $real_base = realpath($base);
    if ($real_base === false) {
        return false;
    }
    return $real === $real_base || strpos($real, $real_base . '/') === 0;
}

/**
 * Relative paths of the flat tree files present under $base (Caddyfile plus
 * conf.d/*.caddy, files only, no subdirectories).
 */
function editor_tree_files($base)
{
    return editor_tree_walk_files($base);
}

/**
 * Relative paths of the currently staged files (written by the editor API).
 */
function editor_staged_files()
{
    return editor_tree_files(STAGING_DIR);
}

/**
 * Copy a file, creating parent directories as needed.
 */
function editor_copy_file($src, $dst)
{
    if (!is_dir(dirname($dst)) && !mkdir(dirname($dst), 0755, true)) {
        return false;
    }
    return copy($src, $dst);
}

/**
 * Recursively remove a directory tree.
 */
function editor_rmtree($dir)
{
    if (!is_dir($dir)) {
        return;
    }
    $items = scandir($dir);
    if ($items === false) {
        return;
    }
    foreach ($items as $item) {
        if ($item === '.' || $item === '..') {
            continue;
        }
        $path = $dir . '/' . $item;
        if (is_dir($path) && !is_link($path)) {
            editor_rmtree($path);
        } else {
            @unlink($path);
        }
    }
    @rmdir($dir);
}

/**
 * Envfile used for validation (--envfile), from the plugin settings.
 */
function editor_envfile()
{
    $envfile = '/usr/local/etc/caddy/env';
    $config = Config::getInstance()->object();
    if (isset($config->OPNsense->caddyadvanced->general->EnvFile)) {
        $envfile = (string)$config->OPNsense->caddyadvanced->general->EnvFile;
    }
    return $envfile;
}

/**
 * Whether Caddy is currently running: pidfile present and the process alive.
 * Guards against a stale pidfile causing a pointless reload (and rollback)
 * of an otherwise valid save.
 */
function editor_caddy_running()
{
    $pidfile = '/var/run/caddy/caddy.pid';
    if (!is_file($pidfile)) {
        return false;
    }
    $pid = trim(file_get_contents($pidfile));
    if (!is_numeric($pid)) {
        return false;
    }
    // FreeBSD-native liveness check (the PHP posix extension may be absent).
    exec('kill -0 ' . (int)$pid . ' 2>/dev/null', $o, $code);
    return $code === 0;
}

/**
 * Graceful reload. Returns true on success, 'skipped' when Caddy is not
 * running, or the combined command output on failure.
 */
function editor_reload()
{
    if (!editor_caddy_running()) {
        return 'skipped';
    }
    editor_run_cmd('service caddy reload', $out, $code);
    if ($code !== 0) {
        return trim(implode("\n", $out));
    }
    return true;
}

/**
 * Restore a snapshot over the live tree: rewrite every snapshot file and
 * drop any tree file the snapshot does not contain (e.g. files a failed
 * save had just created).
 */
function editor_restore_snapshot($snapshot)
{
    foreach (editor_tree_files($snapshot) as $rel) {
        if (editor_write_target_ok(BASE . '/' . $rel, BASE)) {
            editor_copy_file($snapshot . '/' . $rel, BASE . '/' . $rel);
        }
    }
    foreach (editor_tree_files(BASE) as $rel) {
        if (!is_file($snapshot . '/' . $rel)) {
            @unlink(BASE . '/' . $rel);
        }
    }
}

/**
 * Keep only the last 5 rollback snapshots.
 */
function editor_prune_snapshots()
{
    $entries = glob(ROLLBACK_DIR . '/*');
    if ($entries === false) {
        return;
    }
    $dirs = array();
    foreach ($entries as $entry) {
        if (is_dir($entry)) {
            $dirs[] = $entry;
        }
    }
    sort($dirs); // timestamped YmdHis names sort chronologically
    $excess = count($dirs) - 5;
    for ($i = 0; $i < $excess; $i++) {
        editor_rmtree($dirs[$i]);
    }
}

/**
 * Record the outcome in the status file and return the result array.
 */
function editor_complete($out, $result, $message, $ts, $rollback = false)
{
    $out['status'] = ($result === 'ok') ? 'ok' : 'failure';
    $out['result'] = $result;
    $out['message'] = $message;
    $out['rollback'] = $rollback;
    $out['last_save'] = $ts;
    file_put_contents(STATUS_FILE, json_encode($out));
    // A failed cycle must not leave the staging area behind: a stale
    // .complete marker plus a stale full-tree copy would make the next
    // single-file save (or a direct configd editor-save) apply the stale
    // snapshot as the intended tree (ticket #244). Success cleans staging
    // explicitly; every failure funnels through here.
    if ($result !== 'ok') {
        editor_rmtree(STAGING_DIR);
    }
    return $out;
}

/**
 * The save cycle: validate the staged tree, snapshot, atomic apply, reload.
 */
function editor_save_cycle()
{
    $ts = time();
    $out = array(
        'status' => 'ok',
        'result' => 'ok',
        'message' => '',
        'rollback' => false,
        'last_save' => $ts,
    );

    $staged = editor_staged_files();
    if (empty($staged)) {
        return editor_complete($out, 'failure', 'nothing staged to save', $ts);
    }

    // A complete staging run (add / copy / move / delete — prepareStaging
    // copies the whole tree) means the staged set IS the intended tree, so
    // validation must run against the staged files alone. Validating
    // BASE + staged instead would keep the original of a renamed/removed
    // file in the temp tree, producing phantom duplicate site definitions.
    $complete = is_file(COMPLETE_STAGING_MARKER);

    // 1. Build the file set to validate: the staged tree, or (single-file
    //    save) the current tree with the staged file overlaid.
    $tmp = sys_get_temp_dir() . '/os-caddy-advanced-validate-' . uniqid();
    if (!mkdir($tmp, 0700, true)) {
        return editor_complete($out, 'failure', "cannot create staging directory $tmp", $ts);
    }

    if (!$complete) {
        foreach (editor_tree_files(BASE) as $rel) {
            if (!editor_copy_file(BASE . '/' . $rel, $tmp . '/' . $rel)) {
                editor_rmtree($tmp);
                return editor_complete($out, 'failure', "cannot stage $rel", $ts);
            }
        }
    }
    foreach ($staged as $rel) {
        if (!editor_copy_file(STAGING_DIR . '/' . $rel, $tmp . '/' . $rel)) {
            editor_rmtree($tmp);
            return editor_complete($out, 'failure', "cannot stage $rel", $ts);
        }
    }

    // 2. Validate the staged tree before touching anything. Imports resolve
    //    relative to the Caddyfile location, so the temp copy keeps the
    //    relative layout.
    $cmd = CADDY_BIN . ' validate --config ' . escapeshellarg($tmp . '/Caddyfile')
        . ' --adapter caddyfile';
    $envfile = editor_envfile();
    if ($envfile !== '' && is_file($envfile)) {
        $cmd .= ' --envfile ' . escapeshellarg($envfile);
    }
    editor_run_cmd($cmd, $lines, $code);
    // Caddy logs its own progress as {"level":"info",...} JSON on stderr,
    // merged into the capture by 2>&1. Drop just those info lines so a
    // failure message is the plain Error: text, not a JSON-prefixed wall —
    // error-level JSON is kept (it may carry the actual failure).
    $validate = trim(implode("\n", preg_grep('/^\s*\{.*"level"\s*:\s*"info"/', $lines, PREG_GREP_INVERT)));
    if ($code !== 0) {
        editor_rmtree($tmp);
        return editor_complete($out, 'failure', 'validation failed: ' . $validate, $ts);
    }

    // 3. Snapshot the current files for rollback.
    $snapshot = ROLLBACK_DIR . '/' . gmdate('YmdHis', $ts);
    if (!mkdir($snapshot, 0700, true)) {
        editor_rmtree($tmp);
        return editor_complete($out, 'failure', "cannot create snapshot $snapshot", $ts);
    }
    foreach (editor_tree_files(BASE) as $rel) {
        if (!editor_copy_file(BASE . '/' . $rel, $snapshot . '/' . $rel)) {
            editor_rmtree($tmp);
            return editor_complete($out, 'failure', "cannot snapshot $rel", $ts);
        }
    }

    // 4. Atomic apply: write each file as <name>.tmp then rename() over the
    //    target. Never truncate in place. The parent dir is re-checked under
    //    base immediately before each write (symlinked conf.d is refused).
    if ($complete) {
        foreach (array_diff(editor_tree_files(BASE), $staged) as $rel) {
            $target = BASE . '/' . $rel;
            if (!editor_write_target_ok($target, BASE) || !unlink($target)) {
                editor_restore_snapshot($snapshot);
                editor_rmtree($tmp);
                return editor_complete($out, 'failure', "cannot delete $rel", $ts, true);
            }
        }
    }
    foreach ($staged as $rel) {
        $target = BASE . '/' . $rel;
        if (!editor_write_target_ok($target, BASE)) {
            editor_restore_snapshot($snapshot);
            editor_rmtree($tmp);
            return editor_complete($out, 'failure', "cannot write $rel", $ts, true);
        }
        $tmpfile = $target . '.tmp';
        if (!copy(STAGING_DIR . '/' . $rel, $tmpfile)) {
            @unlink($tmpfile);
            editor_restore_snapshot($snapshot);
            editor_rmtree($tmp);
            return editor_complete($out, 'failure', "cannot write $rel", $ts, true);
        }
        if (!rename($tmpfile, $target)) {
            @unlink($tmpfile);
            editor_restore_snapshot($snapshot);
            editor_rmtree($tmp);
            return editor_complete($out, 'failure', "cannot write $rel", $ts, true);
        }
    }
    // 5. Graceful reload, skipped silently when the service is stopped.
    $reload = editor_reload();
    if ($reload !== true && $reload !== 'skipped') {
        // 6. Reload failure: restore the snapshot, reload the previous config.
        editor_restore_snapshot($snapshot);
        editor_reload();
        editor_rmtree($tmp);
        return editor_complete(
            $out,
            'failure',
            'reload failed: ' . $reload . '; previous configuration restored',
            $ts,
            true
        );
    }

    // 7. Success: clean up old snapshots and the staging area.
    editor_prune_snapshots();
    editor_rmtree(STAGING_DIR);
    editor_rmtree($tmp);

    if ($reload === 'skipped') {
        return editor_complete($out, 'ok', 'saved; reload skipped (Caddy not running)', $ts);
    }
    return editor_complete($out, 'ok', 'saved; Caddy reloaded', $ts);
}

// Ensure the runtime/state directories exist (0755).
foreach (array(RUN_DIR, STATE_DIR, STAGING_DIR, ROLLBACK_DIR) as $dir) {
    if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
        echo json_encode(array(
            'status' => 'failure',
            'result' => 'failure',
            'message' => "cannot create $dir",
            'rollback' => false,
            'last_save' => 0,
        ));
        exit(1);
    }
    chmod($dir, 0755);
}

// Serialize saves via flock on the editor lock.
$lock = fopen(LOCK_FILE, 'c');
if ($lock === false) {
    echo json_encode(array(
        'status' => 'failure',
        'result' => 'failure',
        'message' => 'cannot open editor lock',
        'rollback' => false,
        'last_save' => 0,
    ));
    exit(1);
}
flock($lock, LOCK_EX);

$result = editor_save_cycle();
flock($lock, LOCK_UN);
fclose($lock);

echo json_encode($result);
exit($result['status'] === 'ok' ? 0 : 1);
