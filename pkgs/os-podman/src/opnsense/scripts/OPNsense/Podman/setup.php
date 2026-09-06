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
        $storageDir = $containersDir . '/storage';
        $storageFiles = is_dir($storageDir) ? @scandir($storageDir) : false;
        $hasExistingStorage = is_array($storageFiles) && count($storageFiles) > 2;
        if (!$hasExistingStorage) {
            log_msg("Creating ZFS dataset zroot/containers mounted at {$containersDir}");
            exec('/sbin/zfs create -o mountpoint=' . escapeshellarg($containersDir) . ' zroot/containers 2>/dev/null');
        } else {
            log_msg("Existing container storage detected in {$storageDir}; skipping zroot/containers creation to avoid mount shadowing");
        }
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
if (!file_exists('/usr/local/etc/containers')) {
    @mkdir('/usr/local/etc/containers', 0755, true);
}

$pluginEnabled = false;
if ($podmanCfg !== null && isset($podmanCfg->general->enabled)) {
    $pluginEnabled = ((string)$podmanCfg->general->enabled === '1');
}

$defaultLinuxPlatform = true;
if ($podmanCfg !== null && isset($podmanCfg->general->default_linux_platform)) {
    $defaultLinuxPlatform = ((string)$podmanCfg->general->default_linux_platform === '1');
}

$dockerAlias = true;
if ($podmanCfg !== null && isset($podmanCfg->general->docker_alias)) {
    $dockerAlias = ((string)$podmanCfg->general->docker_alias === '1');
}

$dockerSearchRegistry = true;
if ($podmanCfg !== null && isset($podmanCfg->general->docker_search_registry)) {
    $dockerSearchRegistry = ((string)$podmanCfg->general->docker_search_registry === '1');
}

if ($dockerSearchRegistry) {
    if (!file_exists($registriesConfPath) || filesize($registriesConfPath) < 5) {
        $registriesContent = "unqualified-search-registries = [\"docker.io\"]\n";
        file_put_contents($registriesConfPath, $registriesContent);
        log_msg("Configured docker.io search registry in {$registriesConfPath}");
    } else {
        $content = file_get_contents($registriesConfPath);
        if (preg_match('/^unqualified-search-registries\s*=/m', $content)) {
            $content = preg_replace('/^unqualified-search-registries\s*=.*$/m', 'unqualified-search-registries = ["docker.io"]', $content);
        } else {
            $content = "unqualified-search-registries = [\"docker.io\"]\n" . $content;
        }
        file_put_contents($registriesConfPath, $content);
        log_msg("Configured docker.io search registry in {$registriesConfPath}");
    }
} else {
    if (file_exists($registriesConfPath)) {
        $content = file_get_contents($registriesConfPath);
        if (preg_match('/^unqualified-search-registries\s*=/m', $content)) {
            $content = preg_replace('/^unqualified-search-registries\s*=.*$/m', 'unqualified-search-registries = []', $content);
            file_put_contents($registriesConfPath, $content);
            log_msg("Cleared unqualified-search-registries in {$registriesConfPath}");
        }
    }
}

// Ensure default share containers.conf sets default volumes for FreeBSD Linuxulator APT mmap workaround
$shareContainersConf = '/usr/local/share/containers/containers.conf';
$aptFreebsdShare = '/usr/local/share/opnware/apt-freebsd.conf';
$aptMountSpec = '/usr/local/share/opnware/apt-freebsd.conf:/etc/apt/apt.conf.d/99freebsd-mmap.conf:ro';

if (!file_exists($aptFreebsdShare)) {
    @mkdir('/usr/local/share/opnware', 0755, true);
    @file_put_contents($aptFreebsdShare, "APT::Cache-Start 268435456;\nAPT::Cache-Limit 268435456;\n");
}

if (!file_exists($shareContainersConf)) {
    @mkdir('/usr/local/share/containers', 0755, true);
    $containersConfContent = "[containers]\nvolumes = [\n  \"{$aptMountSpec}\"\n]\n";
    file_put_contents($shareContainersConf, $containersConfContent);
    log_msg("Created {$shareContainersConf} with default Linuxulator APT mmap volume");
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

// Ensure jail resource accounting is armed in /boot/loader.conf.local
$loaderConf = @file_get_contents('/boot/loader.conf.local') ?: '';
if (strpos($loaderConf, 'kern.racct.enable') === false) {
    @file_put_contents('/boot/loader.conf.local', $loaderConf . "\nkern.racct.enable=\"1\"\n");
    log_msg("Added kern.racct.enable=\"1\" to /boot/loader.conf.local for container resource accounting");
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

// 4. Shell Aliases & Docker CLI Compatibility Symlink
$wrapperBin = '/usr/local/bin/podman-wrapper';
$beginMarker = '# BEGIN OPNWARE PODMAN ALIASES';
$endMarker = '# END OPNWARE PODMAN ALIASES';

$shAliases = [];
$cshAliases = [];

if ($defaultLinuxPlatform) {
    $shAliases[] = 'alias podman="/usr/local/bin/podman-wrapper"';
    $cshAliases[] = 'alias podman /usr/local/bin/podman-wrapper';
}
if ($dockerAlias) {
    $shAliases[] = 'alias docker="/usr/local/bin/podman-wrapper"';
    $cshAliases[] = 'alias docker /usr/local/bin/podman-wrapper';
}

function update_delimited_block(string $filePath, array $lines, string $beginMarker, string $endMarker): void
{
    $content = file_exists($filePath) ? (@file_get_contents($filePath) ?: '') : '';
    $pattern = '/\n?' . preg_quote($beginMarker, '/') . '.*?' . preg_quote($endMarker, '/') . '\n?/s';
    $clean = trim(preg_replace($pattern, '', $content));

    if (!empty($lines)) {
        $block = "{$beginMarker}\n" . implode("\n", $lines) . "\n{$endMarker}\n";
        $newContent = (!empty($clean) ? $clean . "\n\n" : "") . $block;
    } else {
        $newContent = !empty($clean) ? $clean . "\n" : "";
    }

    if ($newContent !== $content) {
        $dir = dirname($filePath);
        if (!is_dir($dir)) {
            @mkdir($dir, 0755, true);
        }
        @file_put_contents($filePath, $newContent);
        chmod($filePath, 0644);
        log_msg("Updated {$filePath} aliases block");
    }
}

// Manage /usr/local/etc/profile.d/podman.sh and /etc/profile.d/podman.sh
if (!empty($shAliases)) {
    foreach (['/usr/local/etc/profile.d', '/etc/profile.d'] as $pDir) {
        if (!is_dir($pDir)) {
            @mkdir($pDir, 0755, true);
        }
        $pFile = "{$pDir}/podman.sh";
        $shContent = "# Generated by os-podman setup\n" . implode("\n", $shAliases) . "\n";
        file_put_contents($pFile, $shContent);
        chmod($pFile, 0644);
        log_msg("Updated {$pFile} with aliases");
    }
} else {
    foreach (['/usr/local/etc/profile.d/podman.sh', '/etc/profile.d/podman.sh'] as $pFile) {
        if (file_exists($pFile)) {
            @unlink($pFile);
            log_msg("Removed {$pFile}");
        }
    }
}

// Manage zsh, bash, and csh init files
$shTargetFiles = [
    '/usr/local/etc/zshenv',
    '/usr/local/etc/zshrc',
    '/usr/local/etc/bash.bashrc',
];
foreach ($shTargetFiles as $shTarget) {
    update_delimited_block($shTarget, $shAliases, $beginMarker, $endMarker);
}

// Manage /etc/csh.cshrc for csh/tcsh shells
update_delimited_block('/etc/csh.cshrc', $cshAliases, $beginMarker, $endMarker);

// Manage /usr/local/bin/docker symlink
$dockerSymlink = '/usr/local/bin/docker';
if ($dockerAlias) {
    if (is_link($dockerSymlink)) {
        if (readlink($dockerSymlink) !== $wrapperBin) {
            @unlink($dockerSymlink);
            @symlink($wrapperBin, $dockerSymlink);
            log_msg("Updated {$dockerSymlink} symlink -> {$wrapperBin}");
        }
    } elseif (!file_exists($dockerSymlink)) {
        @symlink($wrapperBin, $dockerSymlink);
        log_msg("Created {$dockerSymlink} symlink -> {$wrapperBin}");
    }
} else {
    if (is_link($dockerSymlink)) {
        @unlink($dockerSymlink);
        log_msg("Removed {$dockerSymlink} symlink");
    }
}

// 5. Notify Caddy Advanced if installed
if (file_exists('/usr/local/opnsense/version/caddy-advanced')) {
    $backend = new \OPNsense\Core\Backend();
    $backend->configdRun('caddyadvanced dockerproxy-sync');
}

$podmanVersion = '5.8.4';
$verOut = trim(shell_exec('/usr/local/bin/podman --version 2>/dev/null') ?: '');
if (!empty($verOut) && preg_match('/version\s+([^\s]+)/i', $verOut, $m)) {
    $podmanVersion = $m[1];
}

// 6. Record status
$status = [
    'status' => 'ok',
    'version' => $podmanVersion,
    'zfs' => $hasZfs,
    'driver' => $storageDriver,
    'linux_emulation' => $enableLinux,
    'default_linux_platform' => $defaultLinuxPlatform,
    'docker_alias' => $dockerAlias,
    'docker_search_registry' => $dockerSearchRegistry,
    'timestamp' => time()
];
file_put_contents("{$stateDir}/setup_status.json", json_encode($status));

echo json_encode($status) . "\n";
closelog();
