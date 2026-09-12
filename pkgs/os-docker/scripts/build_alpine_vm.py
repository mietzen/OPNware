#!/usr/bin/env python3
import os
import pty
import select
import subprocess
import sys
import time

log_f = open('/tmp/build_alpine.log', 'w')

def log(msg):
    log_f.write(msg + '\n')
    log_f.flush()
    print(msg, flush=True)

# Clean any existing VM state
log("Cleaning any previous VM state...")
os.system('sudo killall -9 cu python3 2>/dev/null')
os.system('sudo bhyvectl --destroy --vm=docker-vm 2>/dev/null')
os.system('sudo vm poweroff docker-vm 2>/dev/null')
os.system('sudo rm -f /var/db/vm/docker-vm/run.lock')
os.system('sudo rm -f /var/spool/lock/LCK..*')
time.sleep(1)

# Ensure os.img and data.img are prepared
os.system('truncate -s 2G /var/db/vm/docker-vm/os.img')
os.system('truncate -s 20G /var/db/vm/docker-vm/data.img')

# Start VM installation from serial-enabled Alpine Virt ISO
log("Starting Alpine installation VM...")
os.system('vm install docker-vm alpine-virt-serial.iso >/dev/null 2>&1 &')
time.sleep(2)

# Connect to serial console via pty + cu
master, slave = pty.openpty()
proc = subprocess.Popen(
    ['cu', '-l', '/dev/nmdm-docker-vm.1B'],
    stdin=slave,
    stdout=slave,
    stderr=slave,
    close_fds=True
)
os.close(slave)

def wait_for(prompt, timeout=60, send_enter_interval=0):
    buf = ''
    start = time.time()
    last_enter = start
    while time.time() - start < timeout:
        if send_enter_interval > 0 and (time.time() - last_enter) >= send_enter_interval:
            try:
                os.write(master, b'\r\n')
            except OSError:
                pass
            last_enter = time.time()
        r, _, _ = select.select([master], [], [], 1)
        if r:
            try:
                chunk = os.read(master, 4096).decode('utf-8', errors='replace')
            except OSError:
                break
            log_f.write(chunk)
            log_f.flush()
            sys.stdout.write(chunk)
            sys.stdout.flush()
            buf += chunk
            if prompt in buf:
                return True
    log(f"Timeout waiting for '{prompt}'. Buffer was: {repr(buf[-200:])}")
    return False

def send_cmd(cmd):
    time.sleep(0.5)
    os.write(master, (cmd + '\r\n').encode('utf-8'))

try:
    log('Waiting for login prompt on serial console...')
    if wait_for('login:', timeout=120, send_enter_interval=3):
        log('\nLogging in as root...')
        send_cmd('root')
        if wait_for('localhost:~#', timeout=30):
            log('\nLogged in successfully!')
            
            # Configure live network
            send_cmd('ifconfig eth0 100.64.0.2 netmask 255.255.255.0 up')
            wait_for('localhost:~#', timeout=10)
            send_cmd('route add default gw 100.64.0.1')
            wait_for('localhost:~#', timeout=10)
            send_cmd('echo "nameserver 1.1.1.1" > /etc/resolv.conf')
            wait_for('localhost:~#', timeout=10)
            
            # Configure HTTP repositories for unauthenticated live bootstrap
            send_cmd('echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/main" > /etc/apk/repositories')
            wait_for('localhost:~#', timeout=10)
            send_cmd('echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/community" >> /etc/apk/repositories')
            wait_for('localhost:~#', timeout=10)
            
            send_cmd('apk update')
            wait_for('localhost:~#', timeout=60)
            log('\nApk updated. Installing Alpine sys to /dev/vda...')
            
            send_cmd('ERASE_DISKS=/dev/vda setup-disk -m sys -s 0 /dev/vda')
            if wait_for('WARNING: Erase the above disk', timeout=30):
                send_cmd('y')
            wait_for('Installation is complete', timeout=180)
            wait_for('localhost:~#', timeout=30)
            log('\nInstallation to /dev/vda complete!')
            
            # Mount rootfs and install packages
            send_cmd('mount /dev/vda2 /mnt')
            wait_for('localhost:~#', timeout=10)
            send_cmd('echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/main" > /mnt/etc/apk/repositories')
            wait_for('localhost:~#', timeout=10)
            send_cmd('echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/community" >> /mnt/etc/apk/repositories')
            wait_for('localhost:~#', timeout=10)
            
            log('\nInstalling guest packages into chroot...')
            send_cmd('chroot /mnt apk add --no-cache docker openssh e2fsprogs iptables curl ca-certificates')
            wait_for('localhost:~#', timeout=180)
            
            log('\nConfiguring guest services and networking...')
            send_cmd('chroot /mnt rc-update add docker default')
            wait_for('localhost:~#', timeout=10)
            send_cmd('chroot /mnt rc-update add sshd default')
            wait_for('localhost:~#', timeout=10)
            send_cmd('chroot /mnt rc-update add networking boot')
            wait_for('localhost:~#', timeout=10)
            
            # Switch repositories inside chroot to HTTPS now that ca-certificates is installed
            send_cmd('echo "https://dl-cdn.alpinelinux.org/alpine/v3.24/main" > /mnt/etc/apk/repositories')
            wait_for('localhost:~#', timeout=10)
            send_cmd('echo "https://dl-cdn.alpinelinux.org/alpine/v3.24/community" >> /mnt/etc/apk/repositories')
            wait_for('localhost:~#', timeout=10)
            
            # Configure static IP in chroot
            send_cmd('echo "auto lo" > /mnt/etc/network/interfaces')
            send_cmd('echo "iface lo inet loopback" >> /mnt/etc/network/interfaces')
            send_cmd('echo "auto eth0" >> /mnt/etc/network/interfaces')
            send_cmd('echo "iface eth0 inet static" >> /mnt/etc/network/interfaces')
            send_cmd('echo "    address 100.64.0.2" >> /mnt/etc/network/interfaces')
            send_cmd('echo "    netmask 255.255.255.0" >> /mnt/etc/network/interfaces')
            send_cmd('echo "    gateway 100.64.0.1" >> /mnt/etc/network/interfaces')
            wait_for('localhost:~#', timeout=10)
            
            # Configure dockerd options to listen on TCP 2375
            send_cmd('echo \'DOCKER_OPTS="-H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375"\' > /mnt/etc/conf.d/docker')
            send_cmd('mkdir -p /mnt/etc/docker && echo \'{"features":{"containerd-snapshotter":false}}\' > /mnt/etc/docker/daemon.json')
            wait_for('localhost:~#', timeout=10)

            # Configure storage init script
            send_cmd('echo "#!/sbin/openrc-run" > /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "description=\\"Format and mount /var/lib/docker data disk\\"" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "depend() { before dockerd; need localmount; }" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "start() {" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "  if [ -b /dev/vdb ]; then" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "    if ! blkid /dev/vdb >/dev/null 2>&1; then mkfs.ext4 -F -L DOCKER_DATA /dev/vdb; fi" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "    mkdir -p /var/lib/docker" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "    if ! mountpoint -q /var/lib/docker; then mount /dev/vdb /var/lib/docker; fi" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "  fi" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "  iptables -I FORWARD 1 -j ACCEPT 2>/dev/null || true" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "  return 0" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('echo "}" >> /mnt/etc/init.d/docker-storage-init')
            send_cmd('chmod 755 /mnt/etc/init.d/docker-storage-init')
            send_cmd('chroot /mnt rc-update add docker-storage-init default')
            wait_for('localhost:~#', timeout=10)
            
            # Ensure serial console is active in inittab and GRUB
            send_cmd("echo 'ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100' >> /mnt/etc/inittab")
            send_cmd("sed -i 's/quiet/console=tty0 console=ttyS0,115200 net.ifnames=0 quiet/' /mnt/boot/grub/grub.cfg 2>/dev/null || true")
            send_cmd("mount -t proc proc /mnt/proc && mount -t sysfs sys /mnt/sys && mount --bind /dev /mnt/dev")
            send_cmd("chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true")
            send_cmd("umount /mnt/proc /mnt/sys /mnt/dev 2>/dev/null || true")
            wait_for('localhost:~#', timeout=10)
            
            # Enable SSH host keys and root access
            send_cmd("chroot /mnt ssh-keygen -A")
            send_cmd("chroot /mnt passwd -d root")
            send_cmd("sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /mnt/etc/ssh/sshd_config")
            send_cmd("echo 'PermitEmptyPasswords yes' >> /mnt/etc/ssh/sshd_config")
            send_cmd("echo 'PasswordAuthentication yes' >> /mnt/etc/ssh/sshd_config")
            send_cmd("mkdir -p /mnt/root/.ssh && chmod 700 /mnt/root/.ssh")
            wait_for('localhost:~#', timeout=10)
            
            # Copy host SSH public key into authorized_keys if present
            if os.path.exists('/var/db/os-docker/id_ed25519.pub'):
                with open('/var/db/os-docker/id_ed25519.pub') as pub_f:
                    pub_key = pub_f.read().strip()
                    send_cmd(f"echo '{pub_key}' >> /mnt/root/.ssh/authorized_keys")
                    send_cmd("chmod 600 /mnt/root/.ssh/authorized_keys")
            wait_for('localhost:~#', timeout=10)
            
            log('\nSyncing and powering off...')
            send_cmd('sync && poweroff')
            wait_for('reboot: Power down', timeout=45)
            log('\nBase image installation complete!')

finally:
    try:
        proc.terminate()
        os.close(master)
    except Exception:
        pass
    log_f.close()
