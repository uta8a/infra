#!/usr/bin/env bash
set -euo pipefail

# Run only on home-k8s-dev-blue via the pinned Nix development shell:
#   nix develop --command bash scripts/generate-production-machine-configs.sh
#
# The generated configs contain cluster PKI and tokens. They deliberately live
# outside the checkout with restrictive permissions and this script refuses to
# overwrite an existing output set.

repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
output_root="${HOME}/.local/share/home-k8s/generated"
final_output_dir="${output_root}/home-k8s-prod"

cleanup() {
  if [[ -n "${staging_dir:-}" && -d "${staging_dir}" ]]; then
    rm -rf "${staging_dir}"
  fi
}
trap cleanup EXIT

if [[ -e "${final_output_dir}" ]]; then
  echo "refusing to replace existing generated configs: ${final_output_dir}" >&2
  exit 1
fi

umask 077
mkdir -p "${output_root}"
chmod 700 "${output_root}"
staging_dir="$(mktemp -d "${output_root}/.home-k8s-prod.XXXXXX")"
output_dir="${staging_dir}"
mkdir "${output_dir}/configs"

cluster_name="home-k8s-prod"
cluster_endpoint="https://k8s.home.arpa:6443"
talos_version="v1.14.2"
kubernetes_version="1.37.1"
physical_installer="factory.talos.dev/installer/d84876dbfddea4bed14e2983c46bb1abd207b0feed954e568505bda4a6dd710e:${talos_version}"
vm_installer="factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:${talos_version}"
secrets_file="${output_dir}/secrets.yaml"
talosconfig_file="${output_dir}/talosconfig"

generate_config() {
  local hostname="$1"
  local installer_image="$2"
  local patch_file="$3"
  local output_file="${output_dir}/configs/${hostname}.yaml"
  local private_patch="${repository_dir}/talos/private/${hostname}-private.yaml"
  local -a patch_args=(--config-patch-control-plane "@${patch_file}")

  if [[ -f "${private_patch}" ]]; then
    patch_args+=(--config-patch-control-plane "@${private_patch}")
  elif [[ "${hostname}" == "home-k8s-prod-red" || "${hostname}" == "home-k8s-prod-green" ]]; then
    echo "missing private disk-selector patch for ${hostname}: ${private_patch}" >&2
    exit 1
  fi

  talosctl gen config "${cluster_name}" "${cluster_endpoint}" \
    --with-secrets "${secrets_file}" \
    --talos-version "${talos_version}" \
    --kubernetes-version "${kubernetes_version}" \
    --dns-domain cluster.local \
    --install-image "${installer_image}" \
    --additional-sans k8s.home.arpa \
    --additional-sans 192.168.30.5 \
    "${patch_args[@]}" \
    --output-types controlplane \
    --output "${output_file}" \
    --with-docs=false \
    --with-examples=false

  talosctl validate --strict --mode metal --config "${output_file}"
}

talosctl gen secrets \
  --talos-version "${talos_version}" \
  --output-file "${secrets_file}"

generate_config \
  home-k8s-prod-red \
  "${physical_installer}" \
  "${repository_dir}/talos/cluster/patches/home-k8s-prod-red.yaml"
generate_config \
  home-k8s-prod-green \
  "${physical_installer}" \
  "${repository_dir}/talos/cluster/patches/home-k8s-prod-green.yaml"
generate_config \
  home-k8s-prod-yellow \
  "${vm_installer}" \
  "${repository_dir}/talos/cluster/patches/home-k8s-prod-yellow.yaml"

talosctl gen config "${cluster_name}" "${cluster_endpoint}" \
  --with-secrets "${secrets_file}" \
  --talos-version "${talos_version}" \
  --kubernetes-version "${kubernetes_version}" \
  --dns-domain cluster.local \
  --additional-sans k8s.home.arpa \
  --additional-sans 192.168.30.5 \
  --output-types talosconfig \
  --output "${talosconfig_file}" \
  --with-docs=false \
  --with-examples=false

chmod 600 "${secrets_file}" "${talosconfig_file}" "${output_dir}/configs/"*.yaml

mv "${output_dir}" "${final_output_dir}"
staging_dir=""

echo "Generated and validated machine configs in ${final_output_dir}"
echo "No apply-config or bootstrap action was performed."
