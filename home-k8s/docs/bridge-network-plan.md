# Bridge network plan

## Intended topology

`enp2s0f1` is moved into `br0`. The host obtains its existing address by DHCP
on `br0`; `br0` keeps the physical NIC MAC address `fc:5c:ee:d5:bb:13` so its
DHCP identity remains stable. Talos VMs attach directly to `br0` and therefore
share `192.168.30.0/24` with the physical control-plane nodes.

```text
homenet-homelab L2
        |
   enp2s0f1 (bridge port; no IP)
        |
      br0 (DHCP: host 192.168.30.60)
        |
   └── home-k8s-prod-yellow (DHCP reservation: 192.168.30.63)
```

## Safety procedure

The remote netplan file is backed up before replacement. `netplan try` gives a
120-second confirmation window and rolls back its runtime changes if the SSH
connection is lost or the change is not accepted. If it reports failure, the
script restores the backed-up file and applies it.

Run only from `home-k8s-dev-blue` over an interactive SSH session:

```bash
cd ~/src/home-k8s
bash scripts/apply-bridge-netplan.sh
```

When netplan prompts, confirm only after SSH reconnects and the host is still
reachable at `192.168.30.60`. No UniFi configuration is changed.
