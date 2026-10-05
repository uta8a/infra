#!/usr/bin/env bash
set -euo pipefail

name="home-k8s-prod-yellow"
mac_address="52:54:00:30:00:63"
state_root="${XDG_STATE_HOME:-${HOME}/.local/state}/home-k8s"
artifact_dir="${HOME_K8S_ARTIFACT_DIR:-${state_root}/artifacts}"
disk_path="${artifact_dir}/${name}.qcow2"
iso_path="${artifact_dir}/talos-v1.14.2-metal-amd64.iso"
xml_path="${artifact_dir}/${name}.xml"
serial_log_path="${artifact_dir}/${name}.serial.log"

umask 077
mkdir -p "${artifact_dir}"
[[ -f "${iso_path}" ]] || { echo "missing ISO: ${iso_path}" >&2; exit 1; }

qemu_path="$(command -v qemu-system-x86_64)"
ovmf_code="$(find /nix/store -path '*-OVMF*/FV/OVMF_CODE.fd' -type f -print -quit)"
ovmf_vars_template="$(find /nix/store -path '*-OVMF*/FV/OVMF_VARS.fd' -type f -print -quit)"
[[ -n "${ovmf_code}" && -n "${ovmf_vars_template}" ]] || { echo 'missing OVMF firmware' >&2; exit 1; }
virsh -c qemu:///system dominfo "${name}" >/dev/null 2>&1 && {
  echo "domain already exists: ${name}" >&2
  exit 1
}

if [[ ! -e "${disk_path}" ]]; then
  qemu-img create -f qcow2 "${disk_path}" 32G
fi

cat > "${xml_path}" <<EOF
<domain type='kvm'>
  <name>${name}</name>
  <memory unit='MiB'>3072</memory>
  <currentMemory unit='MiB'>3072</currentMemory>
  <vcpu placement='static'>2</vcpu>
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    <loader readonly='yes' type='pflash'>${ovmf_code}</loader>
    <nvram template='${ovmf_vars_template}'>${artifact_dir}/${name}-OVMF_VARS.fd</nvram>
    <boot dev='hd'/>
    <boot dev='cdrom'/>
  </os>
  <features><acpi/></features>
  <cpu mode='host-passthrough' check='none' migratable='on'/>
  <devices>
    <emulator>${qemu_path}</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${disk_path}'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${iso_path}'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='bridge'>
      <mac address='${mac_address}'/>
      <source bridge='br0'/>
      <model type='virtio'/>
    </interface>
    <serial type='file'>
      <source path='${serial_log_path}'/>
      <target type='isa-serial' port='0'/>
    </serial>
    <console type='file'>
      <source path='${serial_log_path}'/>
      <target type='serial' port='0'/>
    </console>
  </devices>
</domain>
EOF

virsh -c qemu:///system define "${xml_path}"
virsh -c qemu:///system start "${name}"
