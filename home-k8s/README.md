# home-k8s

おうちk8sの設定ファイル

# Requirements

- secrets.yaml: Talos Linuxの設定ファイルを生成するために必要なSecrets。bitwardenで管理している。

```bash
# 既存のbootstrapまで済んだ環境で実行
talosctl gen secrets --from-controlplane-config controlplane.yaml
```