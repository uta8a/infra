# Operating boundaries

## Ownership

The MacBook checkout is the sole source of truth. Remote content under
`~/src/home-k8s` is a disposable validation copy, not an authoritative
workspace. Codex runs locally on the MacBook and must never be installed on
`home-k8s-dev-blue`.

Ubuntu and apt own the operating system: kernel, firmware, systemd, OpenSSH
server, networking / netplan, and base OS packages. Nix owns only the declared
development and cluster-management CLI toolchain.

## Remote access

Use the configured SSH host alias and the normal remote user. Bitwarden SSH
Agent supplies authentication. Use `sudo` only for a specific necessary
operation; do not use root SSH login.

Do not alter SSH configuration, `authorized_keys`, firewall configuration,
netplan, or UniFi configuration.

## Data handling

Never commit secrets or private hardware inventory. Do not transfer `.git`,
`.env` files, SSH private keys, `secrets.yaml`, `talosconfig`, generated
configs, or actual `*-private.yaml` files from the MacBook checkout to the
remote host. A transfer must be the public allowlist in
`remote-toolchain-runbook.md`, not a blanket sync of the checkout. During an
authorized recovery flow, the remote host may retrieve Bitwarden attachments
into the owner-only temporary/output directory created by
`scripts/recovery-prepare`; those files must not be copied into the checkout.

## Current limits

The user has additionally authorized the Nix-managed libvirt host setup, the
maintenance-mode Talos VM, and generation, validation, application, and
bootstrap of production Talos machine configurations. Generated configurations
and their secrets stay in a protected directory on the remote host, never in
this checkout.

Kubernetes workloads, Cilium, Argo CD, Longhorn, partitioning, LVM, and UniFi
changes remain out of scope until separately and explicitly authorized.
