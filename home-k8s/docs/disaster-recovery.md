# Talos disaster recovery

This procedure rebuilds and validates Talos **machine configurations** from
the public repository plus the existing private and secret material. It does
not apply a configuration, bootstrap etcd, or restore Kubernetes state.

## What is public, private, and secret

- The repository contains topology, IP addresses, MAC addresses, image
  schematics, public Talos patches, and recovery code.
- Disk serial selectors are private hardware inventory. Store the raw YAML
  files in Bitwarden as separate items under `home-k8s / Talos private
  inventory`.
- `secrets.yaml`, `talosconfig`, `kubeconfig`, generated machine configs,
  private keys, tokens, and passwords are secret material. Store
  `secrets.yaml` as an attachment of the Bitwarden item `home-k8s / Talos
  secrets`; it can exceed a secure note's size limit.

For the recovery script, save every raw YAML file as an attachment. The
attachment name must exactly match its filename. The default item names are:

- `home-k8s / Talos secrets`
- `home-k8s / Talos private inventory / home-k8s-prod-red-private.yaml`
- `home-k8s / Talos private inventory / home-k8s-prod-green-private.yaml`

The attachment filenames are `secrets.yaml`,
`home-k8s-prod-red-private.yaml`, and
`home-k8s-prod-green-private.yaml`, respectively.

Environment variables documented by `scripts/recovery-prepare --help` can
substitute organization-specific item names or IDs.

## Installation media and retained data

Red and green now boot from their NVMe disks with their SD cards removed;
yellow boots from its virtual disk with the ISO ejected. These paths were
[verified on 2026-10-06](boot-verification.md). The original SD cards and
their Talos boot images are no longer required for normal operation. Keeping
a ready-to-use card is optional, not a recovery prerequisite.

The inventories distinguish the current `boot` disk from historical or
detached `installationMedia`. The old `/dev/sdb` value is an observation from
the installation session, not a current device or a future write target.

If new installation media is needed, use the recorded `talosVersion` and
`schematicId` in `talos/physical/inventory.yaml` to obtain the matching
`metal-amd64.iso` from the [Talos Image Factory](https://factory.talos.dev/).
The version and schematic describe reproducible boot assets; they do not
contain this cluster's identity or state. Identify the actual removable
device again before writing any image. Do not reset a healthy installed node
just to recreate a spare card. The official
[ISO installation guide](https://docs.siderolabs.com/talos/v1.8/platform-specific-installations/bare-metal-platforms/iso)
also describes preferring the installed disk or removing the ISO after
installation.

Retain the existing `secrets.yaml`, private disk-selector patches, and
administrative credentials in their protected locations, plus suitable etcd
snapshots for cluster-state recovery. Recreating an SD image does not replace
any of them, and does not require generating new cluster secrets. A bootable
SD card alone is not an etcd or application-data backup.

The boot test did not inspect every file on the detached cards. Before
formatting a card for reuse, check for any separately saved files that need
to be retained. Card erasure is a separate, explicitly targeted operation;
no card is erased by this procedure.

## Prepare recovery material

Starting with the nodes booted in Talos maintenance mode and a recovery host
with Git, Nix, and Bitwarden access:

```bash
git clone <public-repository-url> home-k8s
cd home-k8s
nix develop
bw login
export BW_SESSION="$(bw unlock --raw)"
scripts/recovery-prepare --output-dir .recovery/recovery-$(date +%Y%m%d-%H%M%S)
```

The development shell supplies `talosctl`, `bw`, `jq`, and `yq`; do not install
them with apt. `recovery-prepare` uses `umask 077`, retrieves raw YAML into the
owner-only output directory, regenerates each machine config with the stored
`secrets.yaml`, applies both public and private patches, validates with
`talosctl validate`, and queries `talosctl get disks --insecure` only.

The default without `--output-dir` creates a temporary directory and removes
it at exit. Use an explicit new output directory only when a human needs to
inspect the configs before a separately issued apply command.

The script never invokes `apply-config`, `bootstrap`, `reset`, disk wipe,
reboot, or shutdown. Its successful final line is `NO CONFIG HAS BEEN APPLIED.`

## Mandatory human stop before apply

Read the protected disk reports and generated machine config for every node.
For each one, verify all of the following against the physical/virtual machine:

- maintenance endpoint IP and hostname;
- permanent MAC address;
- target install disk and its private disk serial (especially red and green);
- Talos version and Kubernetes API endpoint;
- the specific generated config file.

Only after those checks may a human choose to run an apply command, for
example:

```bash
talosctl apply-config \
  --insecure \
  --nodes 192.168.30.61 \
  --file .recovery/recovery-YYYYMMDD-HHMMSS/generated/home-k8s-prod-red.yaml
```

This example is deliberately not part of the script. Repeat the verification
for each node; an incorrect install selector can destroy the wrong disk.

## Cluster state is a separate recovery problem

Reusing the original `secrets.yaml` preserves the Talos/Kubernetes identity
needed to regenerate compatible machine configs. It does **not** restore etcd
or Kubernetes API state. If every control-plane disk is lost, restoring prior
Kubernetes objects requires a suitable etcd snapshot. GitOps can recreate the
resources that are committed to Git, but the boundary between GitOps-managed
resources and data requiring etcd backup remains a TODO. This repository does
not install or manage an etcd backup system yet.

## After recovery preparation

Keep only the minimum necessary owner-only recovery output. Once the recovery
is complete, securely remove the explicit `.recovery/` directory. Never copy
its contents into the repository or attach them to an issue, pull request, or
terminal transcript.
