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

## Network safety boundary

The host currently receives `192.168.30.60/24` by DHCP on `enp2s0f1` through
netplan. A VM needs an L2 bridge to join `192.168.30.0/24`, but creating one
changes the host network path and may drop SSH. Do not apply a netplan or bridge
change until the required configuration, rollback procedure, predicted outage,
and resulting topology have been presented for explicit approval.

The approved bridge configuration is now active: `br0` carries the host DHCP
address and `enp2s0f1` is its port. The `home-k8s-prod-yellow` VM is attached
to `br0` and remains in Talos maintenance mode. Do not make further netplan or
bridge changes without new, explicit approval.
