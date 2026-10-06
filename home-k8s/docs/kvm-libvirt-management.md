# KVM and libvirt management

The Ubuntu host remains responsible for the kernel, `/dev/kvm`, and systemd.
This repository's Nix flake supplies the version-pinned userspace toolchain:
QEMU, libvirt, and `virt-install` in addition to the Talos CLI tools.

## Service model

`libvirtd` (or the equivalent split libvirt daemons supplied by the pinned Nix
package) is a system service. Entering `nix develop` alone cannot make it
survive a reboot. The service unit and its executable are therefore selected
from the pinned Nix store, while Ubuntu systemd activates that unit.

Before installing or enabling the service, inspect the unit files exported by
the pinned `libvirt` package and use their exact Nix-store paths. Do not
install libvirt, QEMU, or virt-install with apt.

## Activation

The repository creates `.libvirt-system-units`, a local Nix build root, and
the activation script links the exported units into `/etc/systemd/system` only
when no conflicting unit is present. This keeps the exact Nix closure alive
and makes the service start after a reboot.

Run the script only from the remote repository, through the Nix dev shell:

```bash
cd ~/src/home-k8s
nix develop --command bash scripts/activate-libvirt-system.sh
```

The script needs `sudo` for systemd activation. After it finishes, open a new
SSH session and verify:

```bash
cd ~/src/home-k8s
nix develop --command virsh -c qemu:///system version
nix develop --command virsh -c qemu:///system list --all
```

The script also registers libvirt's PolicyKit action metadata and grants only
the local `uta8a` user `org.libvirt.unix.manage`. This is required for that
user to administer `qemu:///system` without a graphical PolicyKit prompt.

## VM runtime state

The yellow VM's qcow2 disk, UEFI NVRAM, serial log, generated domain XML, and
Talos ISO are runtime artifacts. They live outside the checkout at
`~/.local/state/home-k8s/artifacts` by default. Set
`HOME_K8S_ARTIFACT_DIR` only when an explicit alternative runtime location is
needed.

Do not place these files under the repository, even in a gitignored directory.
libvirt can create root-owned NVRAM and log files; Nix then cannot safely read
the checkout as a path flake and `nix develop` fails. Keep runtime state out of
the source tree instead.

### Relocating existing runtime files

Shut down the VM while its original runtime paths still exist, and confirm
`virsh -c qemu:///system domstate home-k8s-prod-yellow` reports `shut off`.
Only then move the files, preserve their metadata, update the persistent
domain definition, and verify every disk, NVRAM, and log path before starting
the VM. Never run recursive `chown` on a live VM's runtime files. Keep the
previous domain definition available until the relocated VM has booted.

The 2026-10-06 relocation moved yellow's files before shutdown and changed
their ownership recursively. Its next start failed with `Setting different
DAC user or group ... which is already in use`. In
[libvirt 12.7's DAC driver](https://raw.githubusercontent.com/libvirt/libvirt/v12.7.0/src/security/security_dac.c),
this means the remembered-label reference count exceeds one after increment
and the file's current UID/GID differs from the requested owner. A missing
original path also causes shutdown's ownership restoration to be skipped.
Moving the file therefore can leave remembered ownership metadata attached
to the inode even after the VM stops.

On Linux, libvirt stores that metadata in
`trusted.libvirt.security.dac`, `trusted.libvirt.security.ref_dac`, and
`trusted.libvirt.security.timestamp_dac`; see
[libvirt's remembered-label implementation](https://raw.githubusercontent.com/libvirt/libvirt/v12.7.0/src/security/security_util.c).
The reference count is not proof that a process still has the disk open.
These trusted attributes require root access to inspect reliably.

`scripts/repair-yellow-dac.sh` audits by default. Its `--repair` mode performs
guarded cleanup of stale DAC metadata for the stopped yellow VM. A human must
run the sudo-requiring repair from the Mac:

```bash
ssh -t home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command bash scripts/repair-yellow-dac.sh --repair'
```

Use this only after confirming that yellow is stopped and no other VM or
process uses the target files. Do not clear unrelated extended attributes or
disable libvirt's ownership management to bypass the error. The script does
not start the VM; a successful repair is not a boot test. Start yellow
separately, then verify Talos API access, Kubernetes readiness, and etcd
membership before shutting down either physical control-plane node.

### Boot verification status

Yellow is a bootstrapped production control-plane node. On 2026-10-06 it
booted from the relocated disk with the ISO ejected, and all three control
planes returned to Kubernetes `Ready` with healthy etcd status. Red and green
also passed their SD-card-free NVMe boot tests on 2026-10-06, one at a time,
with fresh Talos boots and all three control planes healthy afterward. See
[boot verification](boot-verification.md) for evidence and the test sequence.
VM autostart was observed disabled: starting the host's libvirt service alone
does not establish that yellow will start automatically after a host reboot.

## Network safety boundary

The host currently receives `192.168.30.60/24` by DHCP on `enp2s0f1` through
netplan. A VM needs an L2 bridge to join `192.168.30.0/24`, but creating one
changes the host network path and may drop SSH. Do not apply a netplan or bridge
change until the required configuration, rollback procedure, predicted outage,
and resulting topology have been presented for explicit approval.

The approved bridge configuration is now active: `br0` carries the host DHCP
address and `enp2s0f1` is its port. The `home-k8s-prod-yellow` VM is attached
to `br0` as a production control-plane node. Do not make further netplan or
bridge changes without new, explicit approval.
