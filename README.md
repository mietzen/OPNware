![OPNware Logo](OPNware.png)

# OPNware

This is my personal OPNsense `pkg` repository.\
It contains packages that I use or have used:

- [adguardhome](https://adguard.com/en/adguard-home/overview.html) (cross-compiled)
- [blocky](https://github.com/0xERR0R/blocky) (cross-compiled)
- [btop](https://github.com/aristocratos/btop) (redistributed)
- [caddy](https://caddyserver.com/) (cross-compiled)
- [dnsmasq-leases-widget](https://github.com/mietzen/opnsense-dnsmasq-leases-widget) (source pkg)
- [homer](https://homer-demo.netlify.app/) (source pkg)
- [htop](https://htop.dev/) (redistributed)
- [speedtest-go](https://github.com/showwin/speedtest-go) (cross-compiled)
- [traefik](https://traefik.io) (cross-compiled)
- [upsnap](https://github.com/seriousm4x/UpSnap) (cross-compiled)
- [yq](https://mikefarah.gitbook.io/yq) (cross-compiled)
- [zsh](https://git.code.sf.net/p/zsh/code) (source build)

Most of the packages are cross-compiled Go binaries or redistributed FreeBSD pkgs.
Some are built from source in a FreeBSD VM. 

- Binary `pkgs` are installed under `/opt/opnware/pkgs/` and are linked to `/opt/opnware/bin`
- Service `pkgs` are installed under `/opt/opnware/pkgs/`, service files can be found in `/opt/opnware/services/` and are linked to `/etc/rc.d`

## Why

Instead of using a full-blown [FreeBSD poudriere build system](https://github.com/freebsd/poudriere).

I use: 
- GitHub Actions to build and update `pkgs`
- Python scripts to create FreeBSD `pkgs` and a repo layout
- GitHub Pages to mimic a FreeBSD `pkg` repository

This comes at 0 costs and I don't need to maintain a FreeBSD server.

## ⚠️ Package Requests? -> Fork It!

**I will NOT accept or respond to package requests.**

As mentioned above, this is my **personal** repo, it comes "as is". Issues and Discussions are deactived.

You are welcome to [**fork**](https://github.com/mietzen/OPNware/fork) it and build your own `pkg` repo with additional `pkgs`.

The included GitHub workflows are generic and should work once you configure the following repository secrets:

- `APP_ID`
- `APP_PRIVATE_KEY`

For the `actions/create-github-app-token@v2` action. See the [usage guide](https://github.com/actions/create-github-app-token?tab=readme-ov-file#usage) on how to create a GitHub App.

The App will need these permissions:

- **Contents:** Read/Write
- **Pull requests:** Read/Write

## Installation

Open an `ssh` session on your OPNsense/FreeBSD box and run:

```sh
fetch -o /usr/local/etc/pkg/repos/opnware.conf https://mietzen.github.io/OPNware/opnware.conf
pkg update
````

You can now install packages from this repo.\
For example:

```sh
pkg install btop
```

## Browse

You can browse and download packages directly at:

[https://mietzen.github.io/OPNware/](https://mietzen.github.io/OPNware/)


## Package Licenses

All packages retain their **original upstream licenses**.
Please refer to each project’s repository or documentation for license details.
