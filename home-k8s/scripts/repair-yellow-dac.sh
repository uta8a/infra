#!/usr/bin/env bash
# Human-run, narrowly scoped repair after the 2026-10-06 live artifact move.
# Run through nix develop on home-k8s-dev-blue; sudo must be entered by a human.
set -euo pipefail
export LC_ALL=C

mode="${1:---check}"
if [[ $# -gt 1 || ( "$mode" != --check && "$mode" != --repair ) ]]; then
  echo 'usage: bash scripts/repair-yellow-dac.sh [--check|--repair]' >&2
  exit 2
fi

fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ "$(hostname -s)" == home-k8s-dev-blue ]] || fail 'run only on home-k8s-dev-blue'
[[ "$(id -un)" == uta8a ]] || fail 'run as uta8a; the script elevates only individual commands'

for tool in virsh getfattr setfattr; do
  resolved="$(command -v "$tool")"
  [[ "$resolved" == /nix/store/* ]] || fail "$tool must come from the pinned Nix shell"
done
virsh_bin="$(command -v virsh)"
getfattr_bin="$(command -v getfattr)"
setfattr_bin="$(command -v setfattr)"
[[ -x /usr/bin/lsof ]] || fail 'missing host lsof'

artifact_dir=/home/uta8a/.local/state/home-k8s/artifacts
domain=home-k8s-prod-yellow
files=(
  "$artifact_dir/$domain.qcow2"
  "$artifact_dir/$domain-OVMF_VARS.fd"
  "$artifact_dir/$domain.serial.log"
  "$artifact_dir/talos-v1.14.2-metal-amd64.iso"
)
attrs=(
  trusted.libvirt.security.dac
  trusted.libvirt.security.ref_dac
  trusted.libvirt.security.timestamp_dac
)
attr_pattern='^trusted\.libvirt\.security\.(dac|ref_dac|timestamp_dac)$'

assert_stopped() {
  local state active domains
  state="$("$virsh_bin" -c qemu:///system domstate "$domain")"
  [[ "$state" == 'shut off' ]] || fail 'yellow must be shut off first'
  active="$("$virsh_bin" -c qemu:///system list --name)"
  [[ -z "$active" ]] || fail 'refusing repair while any libvirt domain is active'
  domains="$("$virsh_bin" -c qemu:///system list --all --name)"
  [[ "$domains" == "$domain" ]] || fail 'unexpected domains: review possible shared disks first'
}

assert_files_closed() {
  local output result
  if output="$(sudo /usr/bin/lsof -nP -t -- "${files[@]}" 2>&1)"; then
    fail "an artifact is still open; stop its consumer first: $output"
  else
    result=$?
    [[ "$result" == 1 && -z "$output" ]] || fail "cannot establish that artifacts are closed: $output"
  fi
}

assert_stopped
for file in "${files[@]}"; do
  [[ -f "$file" && ! -L "$file" ]] || fail "not a regular, non-symlink file: $file"
  [[ "$(realpath -e "$file")" == "$file" ]] || fail "unexpected symlink in path: $file"
  [[ "$(stat -c %h "$file")" == 1 ]] || fail "file has another hard link: $file"
done

sudo -v
assert_files_closed
snapshots=()
for file in "${files[@]}"; do
  stat -c '%U:%G %a %n' "$file"
  snapshot="$(sudo "$getfattr_bin" --absolute-names -d -e hex -m "$attr_pattern" -- "$file")"
  printf '%s\n' "$snapshot"
  snapshots+=("$snapshot")
  count="$(printf '%s\n' "$snapshot" | awk '/^trusted\.libvirt\.security\./ { n++ } END { print n+0 }')"
  [[ "$count" == 0 || "$count" == 3 ]] || fail "incomplete DAC metadata; inspect manually: $file"
  if [[ "$count" == 3 ]]; then
    refs="$(sudo "$getfattr_bin" --absolute-names --only-values -n trusted.libvirt.security.ref_dac -- "$file")"
    [[ "$refs" =~ ^[1-9][0-9]*$ ]] || fail "unexpected DAC reference count: $file"
  fi
done

if [[ "$mode" == --check ]]; then
  echo 'Audit only; no attributes changed.'
  exit 0
fi

# Keep the exact original metadata outside Git. Restore only after rechecking
# that the VM is stopped, using getfattr/setfattr's --restore format.
umask 077
backup_dir="$(mktemp -d /home/uta8a/.local/state/home-k8s/dac-backup.XXXXXX)"
for index in "${!files[@]}"; do
  printf '%s\n' "${snapshots[$index]}" > "$backup_dir/$(basename "${files[$index]}").xattrs"
done
printf 'Original DAC metadata backed up to %s\n' "$backup_dir"

# No concurrent virsh/QEMU operations may be run during this short repair.
assert_stopped
assert_files_closed
for index in "${!files[@]}"; do
  file="${files[$index]}"
  current="$(sudo "$getfattr_bin" --absolute-names -d -e hex -m "$attr_pattern" -- "$file")"
  [[ "$current" == "${snapshots[$index]}" ]] || fail "DAC metadata changed during audit: $file"
done
for index in "${!files[@]}"; do
  file="${files[$index]}"
  for attr in "${attrs[@]}"; do
    if [[ "${snapshots[$index]}" == *"$attr="* ]]; then
      sudo "$setfattr_bin" -x "$attr" -- "$file"
      printf 'Removed stale %s from %s\n' "$attr" "$file"
    fi
  done
done
echo 'DAC metadata repair complete; VM remains stopped. Start and verify it separately.'
