#!/usr/bin/env bash
# Activate Nix-built libvirt units with the Ubuntu systemd manager.
set -euo pipefail

nix build .#libvirt-system-units --out-link .libvirt-system-units

unit_directory="$(readlink -f .libvirt-system-units/lib/systemd/system)"

link_if_unconflicted() {
  local source_path="$1"
  local destination="$2"

  if sudo test -e "${destination}" || sudo test -L "${destination}"; then
    local current_target expected_target
    current_target="$(sudo readlink -f "${destination}" || true)"
    expected_target="$(readlink -f "${source_path}")"

    if [[ "${current_target}" != "${expected_target}" ]]; then
      case "${current_target}" in
        /nix/store/*-libvirt-system-units/*)
          sudo ln -sfn "${source_path}" "${destination}"
          ;;
        *)
          printf 'refusing to replace existing file: %s -> %s\n' \
            "${destination}" "${current_target}" >&2
          exit 1
          ;;
      esac
    fi
  else
    sudo ln -s "${source_path}" "${destination}"
  fi
}

for unit_path in "${unit_directory}"/*; do
  unit_name="$(basename "${unit_path}")"
  link_if_unconflicted "${unit_path}" "/etc/systemd/system/${unit_name}"
done

policy_root="$(readlink -f .libvirt-system-units/share/polkit-1)"
link_if_unconflicted \
  "${policy_root}/actions/org.libvirt.unix.policy" \
  "/usr/share/polkit-1/actions/org.libvirt.unix.policy"
link_if_unconflicted \
  "${policy_root}/actions/org.libvirt.api.policy" \
  "/usr/share/polkit-1/actions/org.libvirt.api.policy"
link_if_unconflicted \
  "${policy_root}/rules.d/50-home-k8s-libvirt.rules" \
  "/etc/polkit-1/rules.d/50-home-k8s-libvirt.rules"
sudo mkdir -p /etc/libvirt
link_if_unconflicted \
  "$(readlink -f .libvirt-system-units/etc/libvirt/qemu.conf)" \
  "/etc/libvirt/qemu.conf"

sudo systemctl daemon-reload
sudo systemctl reset-failed virtqemud.socket
sudo systemctl restart virtqemud.socket
sudo systemctl enable --now virtqemud.socket

printf 'libvirt activation completed; start a new SSH session before using virsh.\n'
