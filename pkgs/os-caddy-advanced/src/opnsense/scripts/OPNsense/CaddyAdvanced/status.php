#!/usr/local/bin/php
<?php

/*
 * OPNware os-caddy-advanced — status details for the WebUI readout.
 *
 * Emits JSON with the running state, caddy version, non-standard modules,
 * the config path and its checksum, and the validation outcome of the
 * current Caddyfile.
 */

$caddy = '/usr/local/bin/caddy';
$config = '/usr/local/etc/caddy/Caddyfile';
$result = array(
    'running' => false,
    'version' => '',
    'modules' => array(),
    'config_path' => $config,
    'checksum' => '',
    'validate' => '',
    'podman_socket_active' => file_exists('/var/run/podman/podman.sock'),
);

function run_cmd($cmd, &$out)
{
    $out = array();
    exec($cmd . ' 2>&1', $out, $code);
    return $code;
}

run_cmd("$caddy version", $ver);
if (!empty($ver)) {
    $result['version'] = trim($ver[0]);
}

run_cmd("$caddy list-modules --skip-standard", $mods);
$cleanMods = array();
foreach ($mods as $line) {
    $line = trim($line);
    if ($line === '' || stripos($line, 'Non-standard modules:') === 0 || stripos($line, 'Standard modules:') === 0) {
        continue;
    }
    $cleanMods[] = $line;
}
$result['modules'] = array_values($cleanMods);

if (is_file($config)) {
    $result['checksum'] = hash_file('sha256', $config);
    $vcode = run_cmd("$caddy validate --config $config --adapter caddyfile", $out);
    $result['validate'] = $vcode === 0 ? 'OK' : trim(implode("\n", $out));
}

if (file_exists('/var/run/caddy/caddy.pid')) {
    $pid = trim(file_get_contents('/var/run/caddy/caddy.pid'));
    if (is_numeric($pid)) {
        // FreeBSD-native liveness check (the PHP posix extension may be absent).
        exec('kill -0 ' . (int)$pid . ' 2>/dev/null', $o, $code);
        $result['running'] = ($code === 0);
    }
}

echo json_encode($result);
exit(0);
