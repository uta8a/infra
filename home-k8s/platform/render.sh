#!/usr/bin/env bash
# ローカル描画のみ。クラスタ認証・クラスタへの書き込みは行わない。
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
case "${1:-}" in
  cilium|argocd) component=$1 ;;
  *) echo "usage: bash platform/render.sh cilium|argocd" >&2; exit 2 ;;
esac
chart=$(jq -er --arg name "$component" '.[$name].chart' "$root/charts.json")
version=$(jq -er --arg name "$component" '.[$name].version' "$root/charts.json")
repository=$(jq -er --arg name "$component" '.[$name].repository' "$root/charts.json")
namespace=$(jq -er --arg name "$component" '.[$name].namespace' "$root/charts.json")
helm template "$component" "$chart" --repo "$repository" \
  --version "$version" --namespace "$namespace" --kube-version 1.37.1 \
  --include-crds -f "$root/$component/values.yaml"
