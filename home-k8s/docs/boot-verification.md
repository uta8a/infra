# Production control-plane boot verification

This procedure verifies that yellow boots from its installed virtual disk and
that red and green boot from their installed NVMe disks with their SD boot
media physically removed. An installed disk, a mounted `EPHEMERAL` volume, or
a previously observed Kubernetes `Ready` condition alone does not prove this.

Run administrative commands from the Mac through SSH to `home-k8s-dev-blue`,
using its pinned Nix shell. Keep credentials, kubeconfigs, and etcd snapshots
outside the repository with owner-only permissions. Use the existing cluster
identity; this test must not regenerate secrets, apply machine configs,
bootstrap etcd, reset nodes, or remove etcd members.

## Recorded results

On 2026-10-06, the human-run DAC repair removed the three stale libvirt DAC
attributes from yellow's qcow2 disk and UEFI NVRAM. The original metadata was
saved on the remote host at
`~/.local/state/home-k8s/dac-backup.<id>`. Yellow was stopped after repair;
repair itself did not test booting. See
[KVM and libvirt management](kvm-libvirt-management.md) for the cause and the
runtime-file relocation rules.

Yellow subsequently passed its disk-only boot test on 2026-10-06:

- Saved its persistent domain XML outside Git, ejected the ISO with
  `virsh change-media home-k8s-prod-yellow sda --eject --config`, then started
  the VM. Both persistent and running block-device lists show an empty CD.
- Authenticated Talos v1.14.2 responded with readiness true. `STATE` is on
  `/dev/vda3` and `EPHEMERAL` on `/dev/vda4` at the relocated runtime path.
- All three etcd members responded with the same leader and applied index,
  no errors, and no learners. All three Kubernetes nodes were `Ready`, all
  system pods were running, and the DNS-endpoint API `/readyz` returned `ok`.
- Saved a pre-test etcd snapshot at
  `~/.local/state/home-k8s/etcd-pre-sd-test.<id>/etcd.snapshot` on blue:
  3,330,080 bytes, directory mode 0700, file mode 0600. The snapshot remains
  outside Git and has not been restore-tested.

Yellow's libvirt autostart was observed disabled; this procedure does not
establish automatic VM startup after a reboot of the Ubuntu host.

Red was then gracefully shut down through its direct Talos API. The shutdown
completed its drain, service-stop, and disk-unmount phases. Afterward red was
unreachable and Kubernetes reported `NotReady,SchedulingDisabled`; green and
yellow remained `Ready`, agreed on green as etcd leader, and served an `ok`
API readiness response through the VIP. CoreDNS recovered on the surviving
nodes.

Red passed its SD-free boot test on 2026-10-06:

- The human confirmed the requested power-off, SD removal, and power-on
  sequence. An authenticated Talos response returned at `192.168.30.61` with
  a new boot identifier and an uptime of 33 seconds.
- Talos v1.14.2 reported readiness true. Disk discovery listed `nvme0n1` and
  loop devices, with no `sdb` boot-media device. `STATE` on `nvme0n1p3` and
  `EPHEMERAL` on `nvme0n1p4` were ready.
- All three etcd members responded with green as the same leader, matching
  applied index `63594`, no errors, and no learners. All three Kubernetes
  nodes were `Ready`; red's shutdown cordon was removed automatically. All
  system pods were running and the DNS-endpoint API `/readyz` returned `ok`.

Green's graceful shutdown completed its drain, service-stop, and disk-unmount
phases. A subsequent fresh check found green unreachable and
`NotReady,SchedulingDisabled`, while red and yellow remained `Ready` with
consistent etcd status, an `ok` API readiness response through the VIP, and
CoreDNS running on the two surviving nodes.

Green passed its SD-free boot test on 2026-10-06:

- After the human confirmed the requested SD removal and power-on sequence,
  its authenticated Talos API returned with a new boot identifier and an
  initial uptime of 44 seconds.
- Disk discovery listed only `nvme0n1` and loop devices, with no `sdb` boot
  medium. `STATE` on `nvme0n1p3` and `EPHEMERAL` on `nvme0n1p4` were ready.
  Talos v1.14.2 subsequently reported readiness true and etcd health `OK`.
- All three etcd members agreed on yellow as leader with applied index
  `168593`, no errors, and no learners. All three Kubernetes nodes were
  `Ready`, green's shutdown cordon was removed automatically, and all system
  pods were running. `/readyz` returned `ok` through
  `https://k8s.home.arpa:6443`.
- Yellow remained running with no ISO inserted. Its host-level autostart
  remained disabled.

All three installation-media-free boot tests are complete. Talos continued
to report MachineStatus stage `booting` with readiness true after recovery;
the evidence above establishes boot and service recovery, not long-term
stability or a clean result from every `talosctl health` stage check. No
Ubuntu-host reboot or etcd snapshot restoration was performed.

## Before taking a physical node down

1. While yellow is stopped, inspect its persistent domain XML and block-device
   list. Confirm that the relocated qcow2 and NVRAM paths exist, that the disk
   is first in the boot order, and that the CD device has no inserted ISO in
   the persistent configuration. An empty CD device is acceptable; an ISO
   fallback would leave disk-only boot unproven.
2. Start yellow through libvirt. Confirm the running definition also has no
   inserted ISO, then obtain a fresh authenticated Talos response from
   `192.168.30.63`. Check the installed Talos version and disk-backed volumes.
3. Confirm red, green, and yellow are all Kubernetes `Ready`. Query etcd
   status on all three nodes: all respond, agree on the leader, and have no
   reported errors. Confirm the expected three members are present and none
   is a learner. Check that the Kubernetes API responds through
   `https://k8s.home.arpa:6443`, not just a direct node address.
4. Before the first physical shutdown, take an etcd snapshot to a private
   remote directory if practical. Record its existence and size without
   exposing its contents. A snapshot contains cluster data and credentials;
   do not put it in Git or treat it as a substitute for working quorum.

Useful read-only checks inside the remote Nix shell are:

```bash
export TALOSCONFIG=/home/uta8a/.local/share/home-k8s/generated/home-k8s-prod/talosconfig
talosctl --endpoints 192.168.30.63 --nodes 192.168.30.61,192.168.30.62,192.168.30.63 etcd status
talosctl --endpoints 192.168.30.63 --nodes 192.168.30.63 etcd members
talosctl --endpoints 192.168.30.63 --nodes 192.168.30.63 version
virsh -c qemu:///system domstate home-k8s-prod-yellow
virsh -c qemu:///system domblklist home-k8s-prod-yellow
```

Use a protected, temporary remote kubeconfig for `kubectl get nodes -o wide`
and `kubectl get --raw=/readyz`. Do not print or copy the kubeconfig into the
checkout. Record fresh results after each transition rather than relying on
cached terminal output.

## Physical sequence: red, then green

Three voting etcd members require two available members for quorum. Perform
the complete sequence for red (`192.168.30.61`) and restore all three members
before repeating it for green (`192.168.30.62`). Keep yellow and the other
physical node running throughout each test.

1. Verify the preconditions above immediately before shutdown. Record the
   target node's current uptime or boot identifier so that its subsequent
   response can be associated with a new boot. Use the pinned CLI's help to
   verify command options before performing lifecycle operations.
2. Request a graceful Talos shutdown of the single target node by its direct
   address. Do not use a multi-node selector and do not use reset. Continue
   monitoring the other two etcd members and the API through the shared VIP.
3. Wait for Talos to complete shutdown. Loss of ping or API access alone does
   not prove that power is off. A human must confirm the physical machine is
   powered off before removing the SD card.
4. The human removes the target node's SD boot media and powers that same
   node on, leaving the other physical node untouched. Record the human's
   confirmation that the SD remains removed. Remote checks cannot establish
   physical removal by themselves.
5. Obtain a fresh authenticated Talos response from the target's direct
   address. Confirm a new boot, the expected node identity and Talos version,
   and persistent volumes on its NVMe disk. Inspect disk and mount resources
   or relevant boot logs if the boot source remains unclear. Do not publish
   private disk serials in the evidence record.
6. Confirm all three etcd members respond without errors, retain the expected
   membership, and agree on the leader. Confirm all three Kubernetes nodes
   are `Ready`, system pods have recovered, and `/readyz` succeeds through
   `k8s.home.arpa`. Only then mark this node's test passed and proceed to the
   next physical node.

Graceful shutdown, human power-off confirmation, SD removal, power-on, and
post-boot verification are separate checkpoints. Do not combine them into an
unattended loop. A successful yellow test does not establish either physical
node's bootability.

## If a node does not return

Keep the other two nodes running and stop the test sequence. Have the human
inspect the failed node's display and firmware boot selection. Restoring the
original SD media, if retained, or equivalent recreated installation media
for diagnosis requires another confirmed power off. The original cards need
not be preserved; see [recovery media](disaster-recovery.md#installation-media-and-retained-data).
Do not reset, reinstall, re-bootstrap, or change partitions as an
automatic recovery step. Re-establish all three healthy members before
attempting the next shutdown.

## Evidence to record for each node

- Date/time and node name; initial healthy three-member cluster.
- Yellow: persistent and running CD media absent, relocated disk/NVRAM paths,
  and fresh Talos API response after starting the VM.
- Physical nodes: graceful shutdown result, human power-off confirmation,
  explicit SD-removal confirmation, and subsequent power-on.
- Fresh boot identity or uptime, authenticated Talos response, expected
  installed version, and persistent disk/mount evidence.
- All three etcd status checks and membership, three Kubernetes `Ready`
  nodes, and Kubernetes API readiness through the DNS endpoint after recovery.
- Result: passed, failed, or pending, with the exact unresolved checkpoint.

Etcd snapshot files and credential-bearing output remain private. Record only
the protected backup location and non-sensitive observations here.
