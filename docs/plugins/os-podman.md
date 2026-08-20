# OPNware os-podman: User Guide & Architecture Reference

The `os-podman` plugin brings native OCI container management to OPNsense using Podman and `ocijail`. Containers execute directly on the FreeBSD kernel within isolated Jails, utilizing 64-bit Linux binary emulation for Linux containers without the overhead of a virtual machine hypervisor.

---

## 1. Architecture Overview

- **Engine**: Podman 5.8.x with `ocijail` runtime backend.
- **Emulation**: FreeBSD 64-bit Linux kernel emulation (`linux64.ko`, `linprocfs`, `linsysfs`).
- **Storage**: Copy-on-Write ZFS dataset (`zroot/containers`) mounted at `/var/db/containers/storage` (fallback to `vfs` on UFS installations).
- **Networking**: CNI bridge interface (`cni-podman0`, subnet `10.88.0.0/16`) integrated with OPNsense PF firewall anchors (`cni-rdr/*`).
- **API Compatibility**: Docker-compatible REST API daemon listening on `/var/run/podman/podman.sock` and optional TCP/TLS sockets.

---

## 2. Pulling and Running Linux Containers

Because Podman runs natively on FreeBSD, image registry queries default to `OS: "freebsd"`. Since public Docker Hub and Quay images are built for Linux, always specify **`--platform linux/amd64`** (or `--os linux`):

### Interactive Shell
```bash
sudo podman run -it --rm --platform linux/amd64 docker.io/library/debian:latest bash
```

### Pulling Images
```bash
sudo podman pull --platform linux/amd64 alpine:latest
sudo podman pull --platform linux/amd64 ubuntu:latest
```

### Publishing Ports
When running containers with published ports (`-p host_port:container_port`), CNI generates packet redirection rules in PF:
```bash
sudo podman run -d --name nginx -p 8080:80 --platform linux/amd64 docker.io/library/nginx:alpine
```
- **Access from LAN/Clients**: Open `http://<OPNSENSE_IP>:8080` from any device on your network.
- **Access from Host CLI**: Connect directly to the container's IP (`http://10.88.0.x:8080`).

---

## 3. ELF Fallback Branding for Go Binaries

Pure Go binaries compiled for Linux (`CGO_ENABLED=0`, e.g., Portainer, Traefik, Hugo, Caddy) omit standard GNU `.note.ABI-tag` ELF metadata. On FreeBSD, unbranded ELF binaries are executed under Linux 64-bit emulation by setting:
```bash
sudo sysctl kern.elf64.fallback_brand=3 kern.elf32.fallback_brand=3
```
*(This is configured automatically during service startup and setup).*

---

## 4. Socket Mounting & Portainer CE

### FreeBSD `nullfs` Socket Inode Limitation
On FreeBSD, `nullfs` (bind-mount driver) can only mount **directories**, not individual socket file inodes. To expose Podman's Docker API socket to containers on the host, mount the containing directory `-v /var/run/podman:/var/run/podman:rw`.

### Deploying Portainer CE
```bash
sudo podman run -d \
  --name portainer \
  --restart=always \
  -p 9000:9000 \
  -p 9443:9443 \
  -v /var/run/podman:/var/run/podman:rw \
  -v portainer_data:/data \
  --platform linux/amd64 \
  docker.io/portainer/portainer-ce:latest \
  -H unix:///var/run/podman/podman.sock
```

Open **`https://<OPNSENSE_IP>:9443`** in your browser to complete initial administrative setup.

---

## 5. Remote Client Access (SSH, TCP, and TLS)

Containers on OPNsense can be managed remotely from your workstation using Docker CLI, Docker Compose, VS Code, or Podman Remote:

### Option A: SSH Context (Docker CLI & Podman Remote)
- **Root Privileges Required**: FreeBSD kernel Jails and CNI networking require root privileges (rootless mode is unsupported on FreeBSD). Remote SSH tunnels must connect as `root@<OPNSENSE_IP>`.
- **Enabling Root SSH in OPNsense**: Navigate to **System → Settings → Administration**, ensure **Permit root user login** is enabled (public key authentication recommended), and add your SSH public key to the root user.
- **Connection Examples**:
  ```bash
  # Docker CLI Context over SSH
  docker context create opnsense --docker "host=ssh://root@<OPNSENSE_IP>"
  docker context use opnsense

  # Podman Remote over SSH
  podman system connection add opnsense ssh://root@<OPNSENSE_IP>/var/run/podman/podman.sock
  podman --remote -c opnsense ps
  ```

### Option B: TCP REST API Socket
1. Navigate to **Services → Podman → Settings** in the OPNsense WebUI.
2. Check **Enable TCP Socket**.
3. Set **Listen Address** to your LAN IP (e.g. `10.100.0.1` or `0.0.0.0`) and **Listen Port** to `2375` (or `2376` with TLS).
4. *(Optional)* Check **Enable TLS** and select a Server Certificate and Client CA from OPNsense Trust Manager.
5. Click **Apply**.
6. Connect external clients via `export DOCKER_HOST="tcp://<OPNSENSE_IP>:2375"`.

---

## 6. WebUI Management Dashboard

The OPNsense WebUI provides complete container management under **Services → Podman → Dashboard**:

- **System Stats Bar**: Real-time summary of Running/Total Containers, Active/Total Images, Volumes, and Reclaimable Disk Space.
- **System Prune**: One-click cleanup button to remove stopped containers and dangling images.
- **Containers**: Start, Stop, Restart, Force Stop, Interactive Web CLI, View Logs (with ANSI color rendering), Inspect JSON configuration, and Delete.
- **Interactive Container CLI**: Built-in web terminal modal with customizable shell (`/bin/sh`), command history (Up/Down arrow navigation), Stop/Abort execution action, and Ctrl+C interrupt support.
- **Outbound Connectivity & Firewall**: Outbound traffic pass rules and WAN Outbound SNAT for container subnets (`10.88.0.0/16`) are registered automatically in PF alongside CNI port forwarding anchors.
- **Images, Volumes, Networks**: Interactive listing and deletion with confirmation protection.
- **Diagnostics Log Viewer**: Live service and operational daemon logging under **Services → Podman → Log File** (`/ui/diagnostics/log/core/podman`).
