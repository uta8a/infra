#!/usr/bin/env bash
# Apply the repository's bridge configuration with a timed netplan rollback.
set -euo pipefail

source_config="host/netplan/00-installer-config.yaml"
target_config="/etc/netplan/00-installer-config.yaml"
backup_file="$(mktemp)"

if [[ ! -f "${source_config}" ]]; then
  printf 'missing source netplan file: %s\n' "${source_config}" >&2
  exit 1
fi

sudo cp "${target_config}" "${backup_file}"
sudo install -m 600 "${source_config}" "${target_config}"

if sudo netplan try --timeout 120; then
  rm -f "${backup_file}"
  printf 'bridge configuration accepted.\n'
else
  sudo install -m 600 "${backup_file}" "${target_config}"
  sudo netplan apply
  rm -f "${backup_file}"
  printf 'bridge configuration was rolled back.\n' >&2
  exit 1
fi
