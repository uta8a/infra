# Remote Nix toolchain runbook

Nix is installed and the remote dev shell is working. This runbook documents
the current safe transfer and validation flow for `home-k8s-dev-blue`. Execute
every command from the MacBook unless a command is explicitly quoted as remote.

## Historical bootstrap note

First inspect the remote state:

```bash
ssh home-k8s-dev-blue 'command -v nix || true; nix --version 2>/dev/null || true'
```

If Nix is absent, use the official Nix installer for a multi-user Ubuntu
installation. Enable the `nix-command` and `flakes` experimental features. Do
not use apt for Nix or for the managed CLIs.

After installation, open a fresh SSH connection and confirm both commands work
without relying on the installer shell's `PATH`:

```bash
ssh home-k8s-dev-blue 'nix --version; nix flake --help'
```

## Current development shell

The existing checkout contains the pinned flake files:

```text
home-k8s/
├── flake.nix
├── flake.lock
└── README.md
```

`flake.nix` exposes an `x86_64-linux` shell with `git`, `curl`, `cacert`,
`talosctl`, `kubectl`, `bitwarden-cli`, `jq`, and `yq-go`, plus the declared
QEMU/libvirt tools. `flake.lock` pins `nixpkgs`. The normal remote entry point
is `nix develop`.

## Copy public files and verify remotely

Create or update the safe remote validation copy at `~/src/home-k8s`. Transfer
only the public allowlist below. Do not copy `.git`, `.env` files, private
keys, `secrets.yaml`, `talosconfig`, generated configs, or actual
`*-private.yaml` files. `--relative` preserves the repository directory
structure; do not add `--delete`.

```bash
cd /Users/uta8a/.ghq/github.com/uta8a/infra/home-k8s

rsync -avR \
  --exclude='*-private.yaml' \
  --exclude='.recovery/' \
  --exclude='generated/' \
  --exclude='secrets/' \
  ./.gitignore ./AGENTS.md ./README.md ./flake.nix ./flake.lock \
  ./docs ./scripts ./talos ./host \
  home-k8s-dev-blue:~/src/home-k8s/
```

From the remote copy, run each check through the dev shell:

```bash
ssh home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command git --version'
ssh home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command curl --version'
ssh home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command talosctl version --client'
ssh home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command kubectl version --client'
ssh home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command bw --version'
ssh home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command jq --version'
ssh home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command yq --version'
```

Verify each resolved executable is in the Nix store:

```bash
ssh home-k8s-dev-blue '
  cd ~/src/home-k8s &&
  nix develop --command sh -c '\''
    command -v git
    command -v curl
    command -v talosctl
    command -v kubectl
    command -v bw
    command -v jq
    command -v yq
  '\''
'
```

For recovery preparation after Bitwarden attachments have been verified, see
[`disaster-recovery.md`](disaster-recovery.md). Stop after the Nix-store paths
and client-version checks are confirmed unless recovery work is explicitly in
scope.
