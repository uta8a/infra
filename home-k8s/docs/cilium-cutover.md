# Flannel から Cilium への移行

2026-11-09、全台の修正後 boot ID が一致し、80分以上の稼働を確認した。
移行前は Flannel / kube-proxy が各3台、CoreDNS が2台。既存アプリ、PVC、
NetworkPolicy、PDB はなかった。Talos 設定、etcd snapshot と既存ネットワーク
リソースを開発ホストの保護領域に保存する。

Cilium 1.21.0-pre.4 を Flannel と併設する。Flannel の `10.244.0.0/16`、
VXLAN UDP 4789 に対し、Cilium は `10.245.0.0/16`、VXLAN UDP 8473 を使用する。
cluster-pool IPAM は移行後も維持する。Talos が持つ既存 Node PodCIDR は残る。
[Ciliumの移行手順](https://docs.cilium.io/en/latest/installation/k8s-install-migration/)に沿って
最初は CNI 設定の自動書き込みとポリシー適用を無効にする。Service の処理は
kube-proxy に任せ、CNI の切り替えと Service datapath の切り替えを分ける。
通常稼働中の全ノードはコントロールプレーンのため、アプリ配置対象外の yellow を
最初の検証対象にする。

1. `values.yaml` と `values-migration.yaml` を順に重ねて描画・レビューする。
   併設後に Cilium、Flannel、kube-proxy、CoreDNS の Ready と API を確認する。
2. `migration-node-config.yaml` の対象ラベルを1台ずつ付け、対象ノードの Cilium
   を再作成する。`05-cilium.conflist` が作られても `10-flannel.conflist` を維持する。
   各台で旧 Pod を入れ替え、Pod IP、DNS、API Service、ノード間通信と etcd を確認する。
3. 初期検証で失敗した場合は次のノードへの移行を止める。対象ラベルを外し、対象 Cilium
   を再作成して `05-cilium.conflist` を書き込まない状態へ戻す。対象ノードの
   Cilium agent にマウントされたディレクトリで `05-cilium.conflist` を退避し、
   残した Flannel 設定を確認してからテスト Pod を作り直す。既存 Pod の再作成が必要。
4. 全 Pod が移行してから Cilium をデフォルトにしてポリシーを有効化する。
   Talos の Flannel 自動導入を止め、既存 Flannel リソースの扱いを確認する。
   kube-proxy は維持する。

各段階で API、CoreDNS、ノードの Ready、etcd の全メンバー応答を確認する。
調査時点では同等構成の独立した検証クラスタがないため、yellow の通信試験と
Flannel 復帰試験を行ってから残りのノードへ進む。

併設時、Talos が `cilium_host` の IP を Kubernetes の InternalIP に選んだ。
`KubeNodeConfig.nodeIP.validSubnets` を各ノードの LAN アドレスの `/32` に固定し、
全台の InternalIP と etcd が元の状態に戻ることを確認してから切り替えた。

2026-11-09、yellow で Cilium への切り替え、Flannel への復帰、Cilium への再移行を
試し、各段階で双方向の Pod 通信と DNS を確認した。続いて red、green を移行した。
CoreDNS は対象ノードから片方ずつ退避し、最後は両 Pod が Cilium endpoint として Ready。

Helm release `cilium` は revision 2、chart `1.21.0-pre.4`。定常設定を反映し、全台の
Talos から `KubeFlannelCNIConfig` を削除した。旧 `kube-flannel` DaemonSet を削除し、
旧 CNI ファイルは `.pre-cilium` として退避した。移行用ラベルと CiliumNodeConfig を
削除した後に新規 Pod の IP が `10.245.0.0/16` に属することを確認した。

- Cilium agent / Envoy / kube-proxy は各3/3、operator / CoreDNS は各2/2 Ready。
- API `/readyz`、全3台の etcd、ノード間 HTTP、DNS と ClusterIP の疎通を確認。
- 一時 NetworkPolicy で green からの ingress を許可し、red からの ingress を拒否できた。
  試験用 Pod、Service、NetworkPolicy は削除した。
- 移行前後の etcd snapshot と Talos の設定を保護領域に保存した。Talos 設定は
  `machineconfig v1alpha1` のようにリソースIDを指定して取得する。
  機密設定を処理するコマンドの標準出力と標準エラーは保護領域に保存する。

移行後にノードを1台ずつ再起動し、全台に `05-cilium.conflist` が作成される
ことを確認した。Flannel DaemonSet は再作成されず、新規テスト Pod は全台で
`10.245.0.0/16` の IP を取得し、ノード間 HTTP、DNS、API Service の疎通が通った。
Argo CD の導入と同期試験は [OCI同期方針](argocd-oci.md) を参照する。
