<?php

/*
 * OPNware os-caddy — shared envfile helpers.
 *
 * The envfile (/usr/local/etc/caddy/env, from general.EnvFile) has three
 * writers: setup.php (CADDY_LOG_LEVEL), dockerproxy.php (the CADDY_DOCKER_*
 * / DOCKER_* rows) and the WebUI grid (EnvController). Every read-modify-write
 * must be serialized on the same flock and replace the file atomically, or a
 * concurrent reconfigure/grid save silently loses rows.
 */

/**
 * The envfile path from the plugin settings (default /usr/local/etc/caddy/env).
 */
function envfile_path()
{
    $path = '/usr/local/etc/caddy/env';
    try {
        $cfg = \OPNsense\Core\Config::getInstance()->object();
        if (isset($cfg->OPNsense->caddy->general->EnvFile)
                && (string)$cfg->OPNsense->caddy->general->EnvFile !== '') {
            $path = (string)$cfg->OPNsense->caddy->general->EnvFile;
        }
    } catch (\Throwable $e) {
        // config unavailable in this context — keep the default
    }
    return $path;
}

/**
 * Take the exclusive envfile lock. Returns the lock handle (release with
 * envfile_release) or false.
 */
function envfile_acquire()
{
    if (!is_dir('/var/run/os-caddy-advanced')) {
        @mkdir('/var/run/os-caddy-advanced', 0755, true);
    }
    $lock = fopen('/var/run/os-caddy-advanced/env.lock', 'c');
    if ($lock === false || !flock($lock, LOCK_EX)) {
        if ($lock !== false) {
            fclose($lock);
        }
        return false;
    }
    return $lock;
}

function envfile_release($lock)
{
    if ($lock !== false) {
        flock($lock, LOCK_UN);
        fclose($lock);
    }
}

function envfile_read_rows($path)
{
    $rows = array();
    if (is_file($path)) {
        $rows = file($path, FILE_IGNORE_NEW_LINES);
    }
    return $rows;
}

/**
 * Set (or append) one row, keeping the first occurrence position and dropping
 * later duplicates — "later duplicates win" on the file means the last value
 * is authoritative, so only the last occurrence is kept.
 */
function envfile_set_row(array &$rows, $name, $value)
{
    $last = -1;
    foreach ($rows as $i => $line) {
        if (preg_match('/^' . preg_quote($name, '/') . '=/', $line)) {
            $last = $i;
        }
    }
    $row = $name . '=' . $value;
    if ($last >= 0) {
        $rows[$last] = $row;
    } else {
        $rows[] = $row;
    }
}

/**
 * Drop every row whose name is in $names (the plugin-owned docker rows).
 */
function envfile_unset_rows(array &$rows, array $names)
{
    $keep = array();
    foreach ($rows as $line) {
        $drop = false;
        foreach ($names as $name) {
            if (preg_match('/^' . preg_quote($name, '/') . '=/', $line)) {
                $drop = true;
                break;
            }
        }
        if (!$drop) {
            $keep[] = $line;
        }
    }
    $rows = $keep;
}

/**
 * Replace the envfile atomically (temp + rename, 0600, never truncate in
 * place). Returns null on success or an error string.
 */
function envfile_write_atomic($path, array $rows)
{
    $dir = dirname($path);
    if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
        return "cannot create $dir";
    }
    $tmp = $dir . '/.env-' . uniqid('', true) . '.tmp';
    if (file_put_contents($tmp, implode("\n", $rows) . "\n") === false) {
        return "cannot write $tmp";
    }
    chmod($tmp, 0600);
    if (!rename($tmp, $path)) {
        @unlink($tmp);
        return "cannot replace $path";
    }
    return null;
}
