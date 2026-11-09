# Longhorn の導入と更新

red・greenの既存NVMe上の `/var/mnt/longhorn` に、V1 Data Engineで各ノードに
1レプリカずつ置く。OpenSearchのPVCでは `storageClassName: longhorn` を明示する。
PVの回収ポリシーは `Retain`。片方のノードが停止すると残り1コピーで稼働し、OpenSearch
のPodの再起動とボリュームの再接続に時間がかかる。検索インデックスはS3から再構築できる。

## Talosの準備

red・greenともに `iscsi-tools` と `util-linux-tools` を確認済み。既存の `/var` は
約510 GBで、確認時の空きは各約495 GB。両ノードの公開パッチに
`UserVolumeConfig` の `volumeType: directory` とディスク登録ラベルを定義する。
ディレクトリは既存の `EPHEMERAL` 上に作成し、Talosがkubeletへ伝播する。
この変更でパーティション作成やフォーマットは発生しない。yellowは対象外とする。

現在稼働中の設定にこの差分だけを反映する。適用前に差分をレビューし、red・greenを
1台ずつ作業する。各ノードが `Ready` に戻り、`talosctl get volumestatus u-longhorn` と
`talosctl get mountstatus u-longhorn` で `/var/mnt/longhorn` が利用可能になってから
Longhornを同期する。Longhorn V1のエンジン起動に備え、`talosctl read /proc/1/mountinfo` で
`/var` と `/var/mnt/longhorn` に `noexec` が付いていないことも確認する。

Longhornがディスクを初回登録する際に容量の70%を予約する。過剰割り当ては100%とし、
各ノードのレプリカの要求容量は合計で約153 GBまでとする。ディスクの空きが25%の閾値に
達すると新規レプリカの配置を止める。これらはスケジューリング条件であり、既存ボリューム
の書き込みやスナップショットに対するファイルシステムの容量制限ではない。
ノードの空き容量とLonghornのスナップショット使用量を確認する。

## OCI同期と動作確認

1. mainのGitHub Actionsで配布された `ghcr.io/uta8a/infra/home-k8s-app` のdigestを取得する。
   [Application例](application.example.yaml)の `targetRevision` をそのdigestに置き換える。
2. `longhorn-system` 専用namespaceのPod Securityラベル、CRDとRBACの差分を確認し、
   Argo CDで手動同期する。更新時も固定版のchartとvaluesをレビューし、digestを更新する。
3. `longhorn` StorageClassが非デフォルト、レプリカ数2、回収ポリシー `Retain` であることを確認する。
   LonghornのNodeリソースでred・greenに `/var/mnt/longhorn` が1つずつ登録され、予約容量が反映されていることを確認する。
4. テストPVCにred上のPodからファイルを書き、Podを削除してデタッチを待つ。同じPVCをgreen上の
   Podでマウントし、ファイルを読み取れることと、レプリカが異なるノードに1つずつあることを確認する。
   テスト後はテスト用PVC、保持されたPV、Longhornボリュームを識別して片付ける。

Kubernetes 1.37.1とTalos 1.14.2はLonghorn 1.13.0の公式リリース時の検証済み構成に
掲載されていない。上記の確認を終えてからOpenSearchを同期する。
Longhornのレプリカは両ノード喪失に備えるバックアップの代わりにはならない。
検索以外のデータを置く際はクラスタ外バックアップとリストアを別途検証する。

[LonghornのTalos要件](https://longhorn.io/docs/1.13.0/advanced-resources/os-distro-specific/talos-linux-support/)
[LonghornのArgo CD導入手順](https://longhorn.io/docs/1.13.0/deploy/install/install-with-argocd/)
[Longhornの検証環境](https://longhorn.io/docs/1.13.0/best-practices/)

[Talosのディレクトリ型ユーザーボリューム](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/storage-and-disk-management/disk-management/user)
