# Cilium / Argo CD 導入準備

## 状態と適用境界

2026-11-09 JST、開発ホストから既存 Talos 認証を使用し、保護された一時
kubeconfig で Kubernetes API を読み取り確認した。認証情報は表示・保存しない。

| 項目 | 実測 |
| --- | --- |
| Talos / Kubernetes | v1.14.2 / v1.37.1 |
| ノード | red / green / yellow、全台 Ready |
| CNI | kube-system/kube-flannel、3/3 Ready |
| Service proxy | kube-system/kube-proxy、3/3 Ready |
| CoreDNS | 2/2 Ready |
| PodCIDR | red: 10.244.0.0/24、yellow: 10.244.1.0/24、green: 10.244.2.0/24 |
| Service | Kubernetes: 10.96.0.1、DNS: 10.96.0.10 |
| スケジューリング | red / green: taint なし、yellow: control-plane NoSchedule |
| Argo CD | Deployment / Service は存在しない |

標準 kubeconfig の current-context は未設定。上記は Secrets の列挙や
Talos 設定変更を行わず確認したスナップショットで、継続的な健全性保証ではない。

今回の対象は基盤の設計・設定・ローカル描画まで。クラスタ適用、Talos 設定変更、
ノード再起動、既存 CNI 削除、Cloudflare / DNS 変更は行っていない。
PWA、OpenSearch、Longhorn、Importer は今回追加しない。

## バージョンと停止条件

候補を Cilium chart 1.21.0-pre.4、Argo CD chart 10.17.0（app v3.6.1）に固定した。
バージョンは `platform/charts.json`、値は `platform/*/values.yaml` で管理する。

- [Cilium 1.21.0-pre.4 の互換性一覧](https://github.com/cilium/cilium/blob/v1.21.0-pre.4/Documentation/network/kubernetes/compatibility.rst)
  は Kubernetes 1.34–1.37。実環境の 1.37 は一覧に含まれる。
  2026-11-09 にユーザーがこのプレリリースの採用を指定した。
  旧候補 1.20.4 の互換性上の停止条件は解消したが、実機での動作保証ではない。
  同等 Talos 環境での移行・復旧検証と本番適用の承認は引き続き必要。
- [Argo CD 3.6 の試験対象](https://github.com/argoproj/argo-cd/blob/v3.6.1/docs/operator-manual/tested-kubernetes-versions.md)
  には Kubernetes 1.37 がある。Helm の描画成功は実クラスタでの動作保証ではない。

## 所有権と目標構成

ネットワーク基盤 Cilium と Argo CD 自体は、初期段階では固定バージョンの Helm
release として管理する。Cilium を Argo CD の prune / self-heal 対象にしない。
Argo CD の自己管理も今回行わない。後続の PWA などを Application に分ける際に、
管理 namespace、許可リポジトリ、AppProject のリソース制限を設計する。
後続アプリの配布元は OCI Registry とし、[OCI 同期方針](argocd-oci.md)に従う。
既存の `home-k8s-app/` は参照も同期もしない。root Application は作成しない。

Cilium の values は **移行完了後の目標設定**であり、Flannel 稼働中に適用する
移行用設定ではない。既存 Node PodCIDR を使う Kubernetes IPAM、VXLAN、
kube-proxy replacement を想定する。Talos 固有の capabilities / cgroup と
host DNS 用 legacy host routing は
[公式 Talos 導入ガイド](https://docs.cilium.io/en/stable/installation/k8s-install-talos-linux/)
に沿う。KubePrism の localhost:7445 は実機で有効性を確認してから使う。
agent は yellow を含む全ノード、operator は red / green に配置する。
red / green の既存ストレージ用ラベルを配置条件に再利用するが、ストレージは導入しない。

Argo CD は単一 replica 構成、ClusterIP / TLS、Ingress なしとする。
UI は当初 localhost の port-forward のみでアクセスし、LAN / Internet 公開しない。
Dex / Notifications は初期段階では無効。ApplicationSet controller は chart 標準の
単一 replica を維持するが、Application / ApplicationSet オブジェクトは作成しない。
admin の初期パスワードは
管理者だけが取得し、ログや Git に出さず変更する。Secret は chart が実行時に生成する。
初期導入のクラスタ権限は広いため、後続 Application の制限とは区別してレビューする。
requests / メモリ limits は初期値であり、負荷計測後に調整する。HA は保証しない。

## CNI 移行の設計ゲート

新規クラスタ向けの Helm install をこのクラスタへそのまま実行しない。
[公式移行手順](https://docs.cilium.io/en/stable/installation/k8s-install-migration/)
を基に、互換性解消後に別の変更として移行用 values とノード単位の手順を作る。

1. 再調査で node labels / taints、Pod、DaemonSet、CNI 設定、KubePrism、
   Talos の現在設定を確認する。etcd バックアップと復旧手順・認証の有効性を確認する。
2. Flannel と Cilium の併存期間の別 Pod CIDR / トンネルポート、IPAM、
   CNI 設定の所有権を設計する。既存 VXLAN と同じ設定で併存させない。
   最終 values と移行 values を区別する。全停止方式を採るなら停止範囲も別途承認する。
3. Talos の Flannel 自動導入を止める設定、kube-proxy の扱い、
   移行中の API / DNS 到達性を同等 Talos 環境で確認する。
   Talos 設定の source of truth と生成スクリプト更新も同じ変更に含める。
4. yellow を含むノードの段階移行と Pod 再作成を設計する。control-plane は
   一度に複数台止めない。各段階で API、etcd quorum、DNS、ノード間通信を確認する。
5. Flannel 管理 Pod が残っていないことを確認した後だけ旧リソースを整理する。
   kube-proxy replacement は移行と同時に無条件で切り替えず、独立した検証境界を置く。
6. API / DNS 不通、Cilium agent 未 Ready、etcd 異常で直ちに中断する。
   単純な `helm uninstall` は CNI の復旧にならない。旧 Talos / CNI 設定復元、
   Pod 再作成までを含むロールバックを事前検証する。reset / wipe は行わない。

このゲート未完了のため、適用用スクリプトや一括削除コマンドは提供しない。

## 描画・レビュー

開発ホストの Nix shell に `kubernetes-helm` を追加した。転送は
[既存の公開ファイル allowlist](remote-toolchain-runbook.md) に `./platform` を追加する。
生成物は Git 外の一時領域へ置き、chart が生成した Secret をログへ表示しない。

```bash
cd ~/src/home-k8s
nix develop --command bash -c '
  set -euo pipefail
  umask 077
  review_dir=$(mktemp -d)
  echo "review directory: $review_dir"
  bash platform/render.sh cilium > "$review_dir/cilium.yaml"
  bash platform/render.sh argocd > "$review_dir/argocd.yaml"
'
```

描画には公開 Helm repository への接続が必要。クラスタへの接続は不要。
CRD / ClusterRole / ClusterRoleBinding、DaemonSet の host mount / capabilities、
配置条件、外部公開の有無、requests / limits をレビューする。
Argo CD namespace は別途作成対象としてレビューする（Pod Security は初期値を継承）。

適用承認の直前に、対象 context と API endpoint を明示し、現状を再取得する。
`kubectl diff` は admission webhook の dry-run を伴い得るため、ローカル描画と区別する。
差分に Secret が含まれる場合はその内容を出力しない。新規 namespace / CRD は
未作成の状態では全差分を評価できないことも記録する。
Helm release の所有権と既存リソースが衝突した場合は takeover / force を使わず止める。

## 適用後の受入条件（未実施）

- Cilium agent 全3台、operator 2台が Ready。API / DNS / ノード間 Pod 通信が正常。
- 許可・拒否それぞれの NetworkPolicy と Service 到達性を専用テストで確認する。
  テスト Pod の作成も適用承認後に行う。
- Argo CD 全コンポーネント正常、port-forward 経由の HTTPS ログイン成功。
  NodePort / LoadBalancer / Ingress が追加されていない。
- 初期パスワード変更と復旧経路確認。自動同期が存在しないことを確認。
- Cilium は移行中の障害復旧、Argo CD は固定 chart / values による再構築を確認する。
  Argo CD release を戻す場合は CRD や後続 Application を不用意に削除しない。

iPhone / Web Push / Cloudflare 検証は後続 Phase 1 に属し、すべて未実施。

## 今回の検証記録

- 開発ホストの Nix store 内の Helm v4.3.0 で旧候補 Cilium 1.20.4 と
  Argo CD chart 10.17.0 を描画できた。
- Cilium 1.21.0-pre.4 への更新後も描画に成功し、agent image が
  `quay.io/cilium/cilium:v1.21.0-pre.4`（chart 指定の digest 付き）になることを確認した。
- OCI Application / AppProject 構成例の YAML 構文と source URL を確認した。
  Argo CD v3.6.1 タグの公式 OCI ガイドにも native OCI source があることを確認した。
- Cilium の Kubernetes IPAM / kube-proxy replacement / legacy host routing、
  agent capabilities から SYS_MODULE が除外されることを描画結果で確認した。
- Argo CD の TLS 有効、Service が ClusterIP（省略時の既定値を含む）、
  red / green 用 nodeSelector、主要コンテナの requests / limits を確認した。
- Argo CD chart に ApplicationSet の `enabled` 設定はないため、その設定は使わず
  標準 controller を維持した。描画の成功だけでは未知の values の検出にはならない。
- `bash -n platform/render.sh`、`git diff --check` を実施した。
- クラスタ側 dry-run / diff、Talos の現在設定と KubePrism、Cilium の実動作、
  CNI 移行・復旧、Argo CD ログインは未検証。適用可能性の承認には使わない。
