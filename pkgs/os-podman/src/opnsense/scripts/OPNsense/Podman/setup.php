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
require_once('certs.inc');

use OPNsense\Core\Config;

function log_msg($msg)
{
    syslog(LOG_NOTICE, "os-podman: " . $msg);
    @file_put_contents('/var/log/podman/system-service.log', date('c') . " [info] " . $msg . "\n", FILE_APPEND);
}

openlog("podman", LOG_PID, LOG_LOCAL4);

$config = Config::getInstance()->object();
$podmanCfg = $config->OPNsense->podman ?? null;

$stateDir = '/var/db/podman';
$runDir = '/var/run/podman';
$logDir = '/var/log/podman';
$etcDir = '/var/etc/podman';
$containersDir = '/var/db/containers';

@mkdir($stateDir, 0755, true);
@mkdir($runDir, 0755, true);
@mkdir($logDir, 0755, true);
@mkdir($etcDir, 0700, true);
@mkdir($containersDir, 0755, true);

// 1. ZFS Container Storage Auto-Provisioning
$hasZfs = false;
$zpoolOut = [];
$zpoolRc = 0;
exec('/sbin/zpool list -H -o name zroot 2>/dev/null', $zpoolOut, $zpoolRc);
if ($zpoolRc === 0 && !empty($zpoolOut)) {
    $hasZfs = true;
    $zfsListOut = [];
    $zfsListRc = 0;
    exec('/sbin/zfs list -H -o name zroot/containers 2>/dev/null', $zfsListOut, $zfsListRc);
    if ($zfsListRc !== 0) {
        log_msg("Creating ZFS dataset zroot/containers mounted at /var/db/containers");
        exec('/sbin/zfs create -o mountpoint=/var/db/containers zroot/containers 2>/dev/null');
    }
}

// Ensure storage.conf exists and reflects driver
$storageDriver = $hasZfs ? 'zfs' : 'vfs';
$storageConfPath = '/usr/local/etc/containers/storage.conf';
if (!file_exists('/usr/local/etc/containers')) {
    @mkdir('/usr/local/etc/containers', 0755, true);
}

$storageConfContent = "[storage]\ndriver = \"{$storageDriver}\"\nrunroot = \"/var/run/containers/storage\"\ngraphroot = \"/var/db/containers/storage\"\n";
file_put_contents($storageConfPath, $storageConfContent);
log_msg("Configured storage driver: {$storageDriver} (/var/db/containers/storage)");

// Ensure registries.conf has default search registries
$registriesConfPath = '/usr/local/etc/containers/registries.conf';
if (!file_exists($registriesConfPath) || filesize($registriesConfPath) < 10) {
    $registriesContent = "unqualified-search-registries = [\"docker.io\", \"quay.io\"]\n";
    file_put_contents($registriesConfPath, $registriesContent);
    log_msg("Configured default search registries in {$registriesConfPath}");
}

// 2. Linux 64-bit Emulation Kernel Modules
$enableLinux = true;
if ($podmanCfg !== null && isset($podmanCfg->general->enable_linux)) {
    $enableLinux = ((string)$podmanCfg->general->enable_linux === '1');
}

if ($enableLinux) {
    log_msg("Initializing 64-bit Linux kernel emulation modules and mounts");
    exec('/sbin/kldload -n linux linux64 linprocfs linsysfs 2>/dev/null');
    exec('/sbin/sysctl kern.elf64.fallback_brand=3 kern.elf32.fallback_brand=3 2>/dev/null');

    @mkdir('/compat/linux/proc', 0755, true);
    @mkdir('/compat/linux/sys', 0755, true);

    $mounts = shell_exec('/sbin/mount 2>/dev/null') ?: '';
    if (strpos($mounts, '/compat/linux/proc') === false) {
        exec('/sbin/mount -t linprocfs linprocfs /compat/linux/proc 2>/dev/null');
    }
    if (strpos($mounts, '/compat/linux/sys') === false) {
        exec('/sbin/mount -t linsysfs linsysfs /compat/linux/sys 2>/dev/null');
    }
}

// 3. TLS Certificate & CA Generation if configured
if ($podmanCfg !== null && !empty((string)$podmanCfg->general->certificate)) {
    $certRefId = (string)$podmanCfg->general->certificate;
    $certObj = null;
    if (isset($config->cert)) {
        foreach ($config->cert as $c) {
            if ((string)$c->refid === $certRefId) {
                $certObj = $c;
                break;
            }
        }
    }
    if ($certObj !== null) {
        $certPem = base64_decode((string)$certObj->crt);
        $keyPem = base64_decode((string)$certObj->prv);
        file_put_contents("{$etcDir}/cert.pem", $certPem);
        file_put_contents("{$etcDir}/key.pem", $keyPem);
        chmod("{$etcDir}/cert.pem", 0644);
        chmod("{$etcDir}/key.pem", 0600);
        log_msg("Exported TLS certificate and private key to {$etcDir}");
    }
}

if ($podmanCfg !== null && !empty((string)$podmanCfg->general->ca)) {
    $caRefId = (string)$podmanCfg->general->ca;
    $caObj = null;
    if (isset($config->ca)) {
        foreach ($config->ca as $ca) {
            if ((string)$ca->refid === $caRefId) {
                $caObj = $ca;
                break;
            }
        }
    }
    if ($caObj !== null) {
        $caPem = base64_decode((string)$caObj->crt);
        file_put_contents("{$etcDir}/ca.pem", $caPem);
        chmod("{$etcDir}/ca.pem", 0644);
        log_msg("Exported CA certificate to {$etcDir}/ca.pem");
    }
}

// 4. Record status
$status = [
    'status' => 'ok',
    'zfs' => $hasZfs,
    'driver' => $storageDriver,
    'linux_emulation' => $enableLinux,
    'timestamp' => time()
];
file_put_contents("{$stateDir}/setup_status.json", json_encode($status));

echo json_encode($status) . "\n";
closelog();
