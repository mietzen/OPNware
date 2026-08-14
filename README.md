![OPNware Logo](OPNware.png)

# OPNware

This is my personal OPNsense `pkg` repository.\
It contains packages that I use or have used:

- [caddy](https://caddyserver.com/) (cross-compiled)
- [homer](https://homer-demo.netlify.app/) (source pkg)
- [htop](https://htop.dev/) (redistributed)
- [yq](https://mikefarah.gitbook.io/yq) (cross-compiled)
- [zsh](https://git.code.sf.net/p/zsh/code) (redistributed)

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

As mentioned above, this is my **personal** repo, at the moment I don't have much time and it comes "as is". If something brakes I will fix it when I get to it, therefore Issues and Discussions are deactived.

You are welcome to [**fork**](https://github.com/mietzen/OPNware/fork) it and build your own `pkg` repo with additional `pkgs`.

The included GitHub workflows are generic and should work once you configure the following repository secrets:

- `APP_ID`
- `APP_PRIVATE_KEY`

For the `actions/create-github-app-token@v2` action. See the [usage guide](https://github.com/actions/create-github-app-token?tab=readme-ov-file#usage) on how to create a GitHub App.

The App will need these permissions:

- **Contents:** Read/Write
- **Pull requests:** Read/Write

### How to add `pkgs`:

1. Copy an existing package folder (e.g. [`pkgs/yq`](https://github.com/mietzen/OPNware/tree/main/pkgs/yq)) and rename it.
2. Fill in `config.yml` — the package spec glossary lives in [`CONTEXT.md`](CONTEXT.md). For a service package add `pkg_service` and look at the [jinja service_template](https://github.com/mietzen/OPNware/blob/main/service_templates/default.jinja).
3. Adjust `build.sh` so it produces your payload, then finishes with `pkg-tool pack`.
4. Build locally (next section). The rest — build matrix, update checks, repo assembly — is driven by pkg-tool and GitHub Actions automatically.

For examples see the [build scripts (`build.sh`)](https://github.com/mietzen/OPNware/blob/main/pkgs/yq/build.sh) and [configs (`config.yml`)](https://github.com/mietzen/OPNware/blob/main/pkgs/yq/config.yml) in the [`pkg` folders](https://github.com/mietzen/OPNware/tree/main/pkgs) and the [main `config.yml`](https://github.com/mietzen/OPNware/blob/main/config.yml).

### Local build & repo preview

Build a package from a plain checkout — no CI env vars needed:

```sh
pip install ./pkg-tool
cd pkgs/yq && ./build.sh amd64 15
```

Build outputs land in `dist/`. Assemble a local repo preview from the repo root and serve it:

```sh
pkg-tool assemble-repo dist config.yml --owner <you> --repo <repo> --output-dir pages
python3 -m http.server 8000 -d pages
```

The generated `pages/opnware.conf` points at the published GitHub Pages URL — for a local test, point it at your server instead:

```
opnware: {
  url: "http://<your-ip>:8000/${ABI}/latest",
  priority: 5,
  enabled: yes
}
```

Then on an OPNsense/FreeBSD box: `fetch -o /usr/local/etc/pkg/repos/opnware.conf http://<your-ip>:8000/opnware.conf`, `pkg update`, and `pkg install <pkg>`.

## Installation

Open an `ssh` session on your OPNsense/FreeBSD box and run:

```sh
fetch -o /usr/local/etc/pkg/repos/opnware.conf https://mietzen.github.io/OPNware/opnware.conf
pkg update
````

You can now install packages from this repo.\
For example:

```sh
pkg install zsh
```

## Browse

You can browse and download packages directly at:

[https://mietzen.github.io/OPNware/](https://mietzen.github.io/OPNware/)


## Package Licenses

All packages retain their **original upstream licenses**.
Please refer to each project’s repository or documentation for license details.
