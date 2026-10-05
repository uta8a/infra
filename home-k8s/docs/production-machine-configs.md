# Production Talos machine configuration

## Non-secret, source-controlled inputs

`talos/cluster/topology.yaml` records the fixed production decisions:

- cluster name: `home-k8s-prod`;
- Kubernetes API endpoint: `https://k8s.home.arpa:6443`;
- Layer-2 Talos control-plane VIP: `192.168.30.5`;
- gateway and DNS resolver: `192.168.30.1`;
- red, green, and yellow node addresses: `.61`, `.62`, and `.63`.

The UniFi Gateway owns the `k8s.home.arpa` A record. It must keep resolving to
the VIP rather than an individual control-plane node. The VIP must not be
leased or reserved by DHCP; it is announced by exactly one Talos control-plane
node at a time after etcd is healthy.

Each node patch pins the management link by its permanent MAC address, applies
the static IP and resolver, and defines the shared VIP. Yellow's public patch
selects its `vda` virtio disk. The physical nodes' NVMe serial selectors are
private inventory and are supplied as separate, Git-ignored patches during
generation; this prevents a boot USB device from matching without publishing
machine-specific identifiers.

## Scheduling and future Longhorn use

Talos taints control-plane nodes `NoSchedule` by default. The red and green
patches remove only that default taint, so normal workloads can run there.
Yellow retains the taint and is therefore excluded from ordinary workload
scheduling.

Red and green receive the label `home-k8s.io/longhorn-storage=true`; yellow
receives `home-k8s.io/longhorn-storage=false`. These labels are planning hooks,
not an installation or enforcement of Longhorn. The physical schematic already
contains `iscsi-tools` and `util-linux-tools`, but no Longhorn volume or mount
is created: no independent data disk has been identified or authorized.

## Generating confidential output

The original generation script creates a *new* Talos identity and is not a
disaster-recovery mechanism. Use it only for an intentional new cluster, never
to reconstruct this cluster. For recovery using the existing identity, follow
[the disaster-recovery guide](disaster-recovery.md).

Run only from the remote host, through the pinned Nix shell:

```bash
ssh home-k8s-dev-blue \
  'cd ~/src/home-k8s && nix develop --command bash scripts/generate-production-machine-configs.sh'
```

The script creates a new shared Talos secrets bundle and derives all three
control-plane configs from it. Its output is protected at:

```text
~/.local/share/home-k8s/generated/home-k8s-prod/
```

The directory and files are owner-only. It contains `secrets.yaml`,
`talosconfig`, and three machine configs and must never be copied into the
checkout, committed, or displayed in terminal output. The script refuses to
overwrite an existing output directory so that an apply-ready set cannot be
silently replaced.

It runs `talosctl validate --strict --mode metal` for every machine config.
Generation and validation do not contact or alter a Talos node.

## Applied and bootstrapped state

On 2026-10-06, each generated machine config was applied through the remote
host using its direct maintenance API address. The three nodes subsequently
accepted authenticated Talos API connections with RBAC enabled. Physical nodes
mounted their NVMe `EPHEMERAL` volumes; yellow mounted `vda4`.

On 2026-10-06, etcd was bootstrapped once on `home-k8s-prod-red` through its
direct address (`192.168.30.61`). All three nodes became consistent etcd
members and the Layer-2 VIP (`192.168.30.5`) began serving the authenticated
Talos API. A read-only Kubernetes API check then confirmed red, green, and
yellow as `Ready` control-plane nodes.

No Cilium, Argo CD, Longhorn, or application workload has been installed.
