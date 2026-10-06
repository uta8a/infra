# home-k8s

This directory is the MacBook-side source of truth for the `home-k8s` Nix
toolchain and the non-secret production Talos topology. The remote development
host is used only through SSH; it is not a Codex installation target.

The repository deliberately excludes generated machine configurations and all
Talos credentials. The source-controlled topology and patches were generated,
validated, and applied to the three control-plane nodes remotely. The cluster
was bootstrapped on 2026-10-06 and its three control-plane nodes are Ready.
On the same date, red and green passed SD-card-free NVMe boot tests, and
yellow booted from its virtual disk with the ISO removed. The
[boot verification record](docs/boot-verification.md) includes the evidence
and remaining limits, including yellow's disabled host-level autostart.
Normal operation no longer needs the SD cards or an attached ISO. The
installation media may be kept as optional recovery tools or recreated from
the recorded Talos version and schematic; they are not cluster backups. See
[recovery media and retained data](docs/disaster-recovery.md#installation-media-and-retained-data).

## Toolchain

On `home-k8s-dev-blue`, enter the pinned toolchain with:

```bash
nix develop
```

The shell provides `git`, `curl`, `cacert`, `talosctl`, `kubectl`, `bw`, `jq`,
and `yq`, as well as `qemu`, `libvirt`, `virt-install`, and `attr` for
`x86_64-linux`.
Its `nixpkgs` revision is recorded in `flake.lock`.

## Documents

- [Remote toolchain runbook](docs/remote-toolchain-runbook.md) — safe
  public-only transfer and Nix-shell validation.
- [Operating boundaries](docs/operating-boundaries.md) — ownership, transfer,
  security, and out-of-scope rules.
- [KVM and libvirt management](docs/kvm-libvirt-management.md) — Nix
  userspace, service activation, and network safety boundary.
- [Boot verification](docs/boot-verification.md) — yellow disk-only boot and
  one-at-a-time physical SD-free boot checks.
- [Production machine configuration](docs/production-machine-configs.md) —
  non-secret topology, protected generated output, validation, and the
  apply-stop boundary.
- [Disaster recovery](docs/disaster-recovery.md) — reconstructing and
  validating machine configs without applying them.
- [Private-material migration checklist](docs/private-material-migration.md) —
  Bitwarden handoff and local cleanup gates.

## Sensitive local material

Public topology and Talos patches live under `talos/`. Disk serials are kept in
Git-ignored `talos/private/*-private.yaml` files and must also be stored in
Bitwarden. Talos `secrets.yaml`, `talosconfig`, `kubeconfig`, and generated
machine configs are credentials or cryptographic material: they never belong
in this checkout. See [talos/private/README.md](talos/private/README.md) and
the disaster-recovery guide before removing any local private material.

Before changing this directory, read [AGENTS.md](AGENTS.md).
