<?php

/**
 *    Copyright (C) 2026 Nils Mietzen
 *
 *    All rights reserved.
 *
 *    Redistribution and use in source and binary forms, with or without
 *    modification, are permitted provided that the following conditions are met:
 *
 *    1. Redistributions of source code must retain the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *
 *    2. Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *
 *    THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 *    INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 *    AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 *    AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 *    OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 *    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 *    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 *    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *    POSSIBILITY OF SUCH DAMAGE.
 */

require_once('config.inc');

use OPNsense\Core\Config;

function log_msg($msg)
{
    syslog(LOG_NOTICE, "os-docker: " . $msg);
    @file_put_contents('/var/log/docker/setup.log', date('c') . " [info] " . $msg . "\n", FILE_APPEND);
}

openlog("docker", LOG_PID, LOG_LOCAL4);

$config = Config::getInstance()->object();
$dockerCfg = $config->OPNsense->docker ?? null;

$stateDir = '/var/db/os-docker';
$runDir = '/var/run/os-docker';
$logDir = '/var/log/docker';
$vmDir = '/var/db/vm/docker-vm';
$shareDir = '/usr/local/share/opnware/docker';

@mkdir($stateDir, 0755, true);
@mkdir($runDir, 0755, true);
@mkdir($logDir, 0755, true);
@mkdir($vmDir, 0755, true);
@mkdir('/var/db/vm', 0755, true);

// 0. Ensure vm-bhyve is enabled and initialized
exec('/usr/sbin/sysrc vm_enable="YES" vm_dir="/var/db/vm" 2>/dev/null');
if (!is_dir('/var/db/vm/.config')) {
    exec('/usr/local/sbin/vm init 2>/dev/null');
}

// 1. Setup vm-bhyve switch docker-net if missing
$swList = [];
exec('/usr/local/sbin/vm switch list 2>/dev/null', $swList);
$hasSwitch = false;
foreach ($swList as $line) {
    if (strpos($line, 'docker-net') !== false) {
        $hasSwitch = true;
        break;
    }
}

if (!$hasSwitch) {
    log_msg("Creating vm-bhyve switch 'docker-net'");
    exec('/usr/local/sbin/vm switch create docker-net 2>/dev/null');
}

$hostIp = (string)($dockerCfg->general->host_ip ?? '100.64.0.1');
$subnet = (string)($dockerCfg->general->subnet ?? '100.64.0.0/24');
$prefixLen = '24';
if (strpos($subnet, '/') !== false) {
    $parts = explode('/', $subnet);
    $prefixLen = $parts[1];
}

exec('/usr/local/sbin/vm switch address docker-net ' . escapeshellarg("{$hostIp}/{$prefixLen}") . ' 2>/dev/null');

// 2. Setup Host SSH Keypair for MicroVM management
$sshKey = "{$stateDir}/id_ed25519";
if (!file_exists($sshKey)) {
    log_msg("Generating SSH management key: {$sshKey}");
    exec("/usr/bin/ssh-keygen -t ed25519 -N '' -f " . escapeshellarg($sshKey) . " -C 'opnsense-docker-mgmt' 2>/dev/null");
    @chmod($sshKey, 0600);
}

// Ensure SSH config directs ssh://root@100.64.0.2 to use the key
$sshClientConfig = <<<EOF
# BEGIN OPNWARE DOCKER SSH
Host 100.64.0.2
    User root
    IdentityFile {$sshKey}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
# END OPNWARE DOCKER SSH
EOF;

@mkdir('/root/.ssh', 0700, true);
$rootSshConf = '/root/.ssh/config';
$existingSsh = file_exists($rootSshConf) ? file_get_contents($rootSshConf) : '';
if (strpos($existingSsh, '# BEGIN OPNWARE DOCKER SSH') !== false) {
    $existingSsh = preg_replace('/# BEGIN OPNWARE DOCKER SSH.*?# END OPNWARE DOCKER SSH\n?/s', $sshClientConfig . "\n", $existingSsh);
} else {
    $existingSsh .= "\n" . $sshClientConfig . "\n";
}
file_put_contents($rootSshConf, $existingSsh);
@chmod($rootSshConf, 0600);

// 3. Base OS Image Setup (os.img)
$osImgTarget = "{$vmDir}/os.img";
$osImgSource = "{$shareDir}/os.img.zst";

if (!file_exists($osImgTarget)) {
    if (file_exists($osImgSource)) {
        log_msg("Extracting deterministic base OS image to {$osImgTarget}");
        exec("/usr/local/bin/zstd -d -f " . escapeshellarg($osImgSource) . " -o " . escapeshellarg($osImgTarget) . " 2>/dev/null");
    } else {
        log_msg("Base OS image archive {$osImgSource} not found yet");
    }
}

// 4. Persistent Data Disk Setup (data.img)
$dataImgTarget = "{$vmDir}/data.img";
$diskSizeGb = (int)($dockerCfg->general->disk_size ?? 20);
if ($diskSizeGb < 5) {
    $diskSizeGb = 20;
}

if (!file_exists($dataImgTarget)) {
    log_msg("Creating {$diskSizeGb}GB sparse data disk at {$dataImgTarget}");
    exec("/usr/bin/truncate -s {$diskSizeGb}G " . escapeshellarg($dataImgTarget) . " 2>/dev/null");
}

// 5. Deploy /usr/local/bin/docker-wrapper
$wrapperPath = '/usr/local/bin/docker-wrapper';
$wrapperContent = <<<'EOF'
#!/bin/sh
# OPNware Docker CLI wrapper: connects seamlessly to the Alpine Linux MicroVM
export DOCKER_HOST="ssh://root@100.64.0.2"
export GIT_SSH_COMMAND="ssh -i /var/db/os-docker/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
exec /usr/local/bin/docker -H ssh://root@100.64.0.2 "$@"
EOF;

file_put_contents($wrapperPath, $wrapperContent);
@chmod($wrapperPath, 0755);

// 6. Manage Shell Profile & Aliases across all FreeBSD shells
$beginMarker = "# BEGIN OPNWARE DOCKER ALIASES";
$endMarker = "# END OPNWARE DOCKER ALIASES";
$aliasBlockSh = "{$beginMarker}\nalias docker='/usr/local/bin/docker-wrapper'\nexport DOCKER_HOST=\"ssh://root@100.64.0.2\"\n{$endMarker}\n";
$aliasBlockCsh = "{$beginMarker}\nalias docker '/usr/local/bin/docker-wrapper'\nsetenv DOCKER_HOST \"ssh://root@100.64.0.2\"\n{$endMarker}\n";

$shProfiles = [
    '/usr/local/etc/zshenv',
    '/usr/local/etc/zshrc',
    '/usr/local/etc/bash.bashrc',
    '/usr/local/etc/profile.d/docker.sh',
    '/etc/profile.d/docker.sh'
];

foreach ($shProfiles as $prof) {
    @mkdir(dirname($prof), 0755, true);
    $content = file_exists($prof) ? file_get_contents($prof) : '';
    if (strpos($content, $beginMarker) !== false) {
        $content = preg_replace('/' . preg_quote($beginMarker, '/') . '.*?' . preg_quote($endMarker, '/') . '\n?/s', $aliasBlockSh, $content);
    } else {
        $content .= "\n" . $aliasBlockSh;
    }
    file_put_contents($prof, $content);
}

// Csh / Tcsh profile
$cshProfiles = ['/etc/csh.cshrc'];
foreach ($cshProfiles as $prof) {
    @mkdir(dirname($prof), 0755, true);
    $content = file_exists($prof) ? file_get_contents($prof) : '';
    if (strpos($content, $beginMarker) !== false) {
        $content = preg_replace('/' . preg_quote($beginMarker, '/') . '.*?' . preg_quote($endMarker, '/') . '\n?/s', $aliasBlockCsh, $content);
    } else {
        $content .= "\n" . $aliasBlockCsh;
    }
    file_put_contents($prof, $content);
}

log_msg("Docker setup completed successfully.");
echo json_encode(["status" => "ok", "message" => "Docker setup completed"]);
