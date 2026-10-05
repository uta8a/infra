# home-k8s agent instructions

## Scope and source of truth

- Work from the MacBook checkout. This directory is the source of truth for
  `home-k8s`.
- Make changes to `home-k8s-dev-blue` only from the MacBook over SSH. Do not
  install Codex or Codex-related software on the remote host.
- Do not create a second `home-k8s` repository or worktree when this directory
  already exists.
- Keep secrets and private inventory out of the repository. Do not copy them
  from the MacBook checkout to the remote host: in particular, do not transfer
  `.git`, `.env`, private keys, `secrets.yaml`, `talosconfig`, generated
  configs, or `*-private.yaml` files. Recovery may retrieve the approved
  Bitwarden attachments into an owner-only temporary directory on the recovery
  host; it must never write them into this checkout.

## Remote host

| Property | Value |
| --- | --- |
| Host | `home-k8s-dev-blue` |
| OS / architecture | Ubuntu Server 26.04.1 LTS / `x86_64-linux` |
| IPv4 / gateway | `192.168.30.60/24` / `192.168.30.1` |
| CPU / RAM | AMD Ryzen 5 PRO 8500GE (6C/12T) / about 14 GiB |
| Storage | `/` about 466 GiB |
| Virtualization | AMD-V and IOMMU enabled; `/dev/kvm` exists |
| Secure Boot | Disabled |

SSH authentication is already available through the Bitwarden SSH Agent. Use
the unprivileged account and elevate only individual remote commands that
require it:

```bash
ssh home-k8s-dev-blue '<command>'
```

Never SSH as root. Do not change SSH configuration, `authorized_keys`,
firewall settings, netplan, or UniFi configuration.

## Toolchain policy

- The remote host's kernel, firmware, systemd, OpenSSH server, networking /
  netplan, and base OS packages remain managed by Ubuntu and apt.
- Manage development and `home-k8s` administration CLIs declaratively with a
  Nix flake. Do not install those CLIs with apt.
- The pinned `x86_64-linux` shell provides `git`, `curl`, `cacert`,
  `talosctl`, `kubectl`, `bitwarden-cli`, `jq`, and `yq-go`, plus the declared
  QEMU/libvirt tools. Pin `nixpkgs` in `flake.lock`.
- Do not place manually downloaded `talosctl` or `kubectl` binaries in
  `/usr/local/bin` or elsewhere on the remote host.

## Approved operating sequence

The Nix bootstrap and initial remote validation are complete. Follow this
sequence for repository changes and recovery work unless the user explicitly
expands scope.

1. Edit and review the MacBook checkout first.
2. Transfer only public files to `~/src/home-k8s`, preserving directory
   structure. Use the explicit `rsync --relative` allowlist in
   `docs/remote-toolchain-runbook.md`; do not use a blanket sync or `--delete`.
3. Validate remote commands through `nix develop --command` and confirm their
   paths resolve from the Nix store.
4. For disaster recovery, use `scripts/recovery-prepare` only. It retrieves
   `secrets.yaml` and private patches as Bitwarden attachments, generates and
   validates configs, and makes read-only maintenance-mode disk queries.
   It must not apply configs, bootstrap, reset, wipe disks, or reboot nodes.

For transfer, validation, and recovery details, follow
[`docs/remote-toolchain-runbook.md`](docs/remote-toolchain-runbook.md).

## Current production-Talos boundary

The initial KVM/libvirt setup and bootstrap of the three production
control-plane nodes are complete. The source-controlled topology and patches
are non-secret; generated machine configs, `talosconfig`, and the secrets
bundle stay outside this checkout. A future `talosctl apply-config` remains a
separate, explicit human action after the recovery checks documented in
`docs/disaster-recovery.md`.

Do not create Kubernetes workloads; configure Cilium, Argo CD, or Longhorn;
modify partitions or LVM; or make UniFi changes without a new, explicit
confirmation.

## Validation expectations

Prefer non-interactive commands such as:

```bash
ssh home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command talosctl version --client'
```

When validating the complete shell, run `git --version`, `curl --version`,
`talosctl version --client`, `kubectl version --client`, `bw --version`,
`jq --version`, and `yq --version`, then inspect `command -v` for each. They
must resolve to Nix-store paths.
