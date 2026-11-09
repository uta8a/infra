# Argo CD の OCI 同期方針

Git を設定の正とし、レビュー済み Kubernetes マニフェストを OCI artifact として
配布する。Argo CD は native OCI source から取得する。選定済み Argo CD v3.6.1
を使い、Git source や Config Management Plugin はこの用途に追加しない。
Argo CD 自体と Cilium の初期導入は引き続き Helm 管理とし、自己管理へは移さない。

## GitHub Actions の配布契約

`uta8a/infra` の main push / workflow_dispatch で GHCR に配布する。
PR はビルド・検証のみで publish 権限を与えない。

| Package | 展開後の内容 | Argo CD の path |
| --- | --- | --- |
| `ghcr.io/uta8a/infra/home-k8s` | Cilium / Argo CD の wrapper chart、固定版の依存 chart、values | `cilium` / `argocd` |
| `ghcr.io/uta8a/infra/home-k8s-app` | linkding の公開マニフェストと Longhorn の固定版 wrapper chart | `linkding` / `longhorn` |

Helm chart ディレクトリは一般 OCI artifact に同梱する。
全体を Helm OCI chart として登録する方式ではない。wrapper の dependency 名の下に
既存 values を配置し、依存 chart を同梱するため、sync 時に外部 Helm repository へ
依存解決しに行かない。releaseName は初期導入と同じ `cilium` / `argocd` を指定する。
`home-k8s-app` に curatedz PWA はまだ含まれない。既存アプリの運用依存・古い
image / 設定の改善は別の変更で行い、配布だけでは導入済みと扱わない。

梱包は `home-k8s/platform/package-oci.py` のファイル allowlist で行う。
Talos 設定、認証情報、生成済み Secret、例示 Application、docs は含めない。
生成物は Git 外の一時領域に作成する。入力ファイルがない・symlink・chart の取得や
描画に失敗した場合は publish 前に停止する。main の Git SHA と run ID / attempt を
含む一意の tag を使い、再実行で既存 tag を上書きしない。latest は更新しない。
OCI manifest に source repository と Git revision を記録し、publish 後の digest を
再取得して単一 layer / media type を検証、Actions summary に残す。
片方の publish 失敗は他方を巻き戻さない。各 package の digest を独立して承認する。

publish job の `GITHUB_TOKEN` に `contents: read` / `packages: write` のみを付与する。
PAT は追加しない。初回 package は private が既定であり、公開設定は変更しない。
既存 package に repository の Actions 書き込み権限がなければ publish は失敗するため、
package の Manage Actions access で `uta8a/infra` を許可する。
registry への push はクラスタ apply や Argo CD の sync を起動しない。

ビルド後・publish直前に `platform/audit-oci.py` でartifactを展開し、ファイルallowlist、
リンクや特殊ファイルの不在、内部chartまで展開したgitleaks検査を必須にする。
検出時は値を表示せず停止する。上流argo-cdのコメント中の `...` のみの秘密鍵記載例は、
3行の完全一致を確認して検査用コピー上でのみコメントへ置換する。配布artifactは変更しない。
gitleaksでは実キーやvaluesファイル全体を除外しない。
スキャナは既知パターンの検査であり、Secret参照やテンプレートの存在そのものを
認証情報混入とは扱わない。上流chartに独自の秘密が埋め込まれていないかも更新時にレビューする。

## 配布契約

- artifact は上記のサブディレクトリを持つ gzip tar の単一 layer とし、
  layer media type は `application/vnd.oci.image.layer.v1.tar+gzip` を使う。
- Application は `repoURL: oci://ghcr.io/uta8a/infra/<package>`、対象の `path`、
  `targetRevision: sha256:<manifest digest>` を指定する。
- Git commit と OCI manifest digest の対応をリリース記録に残す。latest や上書き可能な
  tag を追跡せず、レビュー済み digest を Application 定義で更新する。
- artifact には対象アプリの公開マニフェストだけを含める。Git checkout 全体や
  Secret の実データ、Push 購読情報、秘密を含む ConfigMap を梱包しない。
- 初期段階は手動 sync。automated / prune / selfHeal と Application 削除時の
  cascading finalizer は設定しない。旧 digest を保持し、戻す際も差分をレビューして
  手動 sync する。PVC やデータの復元はマニフェストの巻き戻しと別に扱う。

[v3.6.1 の公式 OCI source ガイド](https://github.com/argoproj/argo-cd/blob/v3.6.1/docs/user-guide/oci.md)では
tag / digest 指定と単一 layer、上記 media type が説明されている。
native OCI source は OCI Helm repository の `enableOCI` 設定とは区別する。
今回は追加の repo-server feature flag / 独自 media type 設定は使わない。

## Application / 権限制限

`platform/argocd/oci-application.example.yaml` は後続 PWA 用の構成例で、
bootstrap の描画には含めない。PWA artifact は未作成、digest もダミーのため、そのまま適用しない。
AppProject は単一の artifact repository と `curatedz` namespace に限定し、
cluster-scoped resource は許可しない。namespace は管理者が別途作成する。
PWA の初期構成に必要な namespaced resource のみ許可し、追加時に見直す。
この制限は Pod の権限制御の代替ではない。Pod Security や ServiceAccount、
NetworkPolicy はワークロード設計時に別途定義する。

## レジストリと認証

上記の GHCR 2 package は公開済み。各 package の公開済み digest を匿名で取得できることを確認した。
公開 artifact なら匿名 pull を優先する。非公開なら Argo CD namespace に
`argocd.argoproj.io/secret-type: repository` の Secret を別途安全に作成し、
`type: oci`、Application と同じ `url`、必要な認証情報を設定する。
pull のみの権限とし、CI の publish 権限を共有しない。
値を values.yaml / artifact / ログへ残さず、更新・失効時の担当と手順も決める。

## アプリを追加するときの確認

1. main マージ後に Actions の publish と summary の digest を確認する。
   workflow_dispatch は main のみ publish する。private package では pull 認証を設定する。
2. artifact の layer 数・media type・内容・digest と Git commit の対応を確認する。
3. AppProject / Application の placeholder を置換し、CRD スキーマを検証する。
   本番適用はユーザー承認後に行う。
4. Argo CD の接続確認・manifest 生成・diff を確認し、対象 namespace 外に差分が
   ないことを確認してから手動 sync。registry 障害時は新規 sync が失敗しても既存
   workload を削除しないことを確認する。
5. 新 digest への更新と旧 digest への復帰を検証する。認証失効・pull 失敗時の
   エラーに秘密が出ないこと、未認可 source / destination が拒否されることを確認する。

公開済み artifact の匿名 pull と Argo CD からの同期は確認済み。
private package の認証と digest を戻す試験は未実施。

2026-11-09、開発ホストで両artifactの生成・展開、内部chart 2個の展開、
allowlist照合とgitleaks検査に成功した。基盤は6ファイル、アプリは2ファイルのみ。
同じ上流valuesパスに合成の秘密鍵形式を混入すると検査が失敗することも確認した。
Helm wrapperの描画、actionlint、シェル構文、`git diff --check` も検証した。
main 配布後は Actions の公開結果と、GHCR から取得した artifact の digest を確認する。

## 手元からのbootstrap

draft PR の設定をレビューし、CNI 移行ゲートを完了してから管理者が手元で適用する。
draft PR 作成は CNI 移行検証の完了を意味しない。初回の Cilium / Argo CD は
`charts.json` の固定版と既存 values を使う Helm 管理とし、OCI の自己同期にはしない。
同ファイルを参照する `platform/render.sh` で最終設定を確認できるが、Cilium は
Flannel 稼働中にそのまま install しない。[移行設計](platform-bootstrap.md)を先に満たす。
Argo CD namespace 作成、固定chartの Helm install、port-forward / 初期認証の確認は
管理者が対象 context と差分を確認して実施する。こちらからはクラスタ操作しない。

OCI package の `cilium` / `argocd` path は将来の管理用に提供するが、初回bootstrapで
Applicationを作成しない。HelmからArgo CDへ所有権を移す場合は別途レビューする。
Longhorn の初回同期は、red・greenのTalosで保存先を準備した後に実施する。[Longhorn 導入手順](../../home-k8s-app/longhorn/README.md)を参照。

## OCI同期の実施結果

Argo CD v3.6.1 の試験用 Application で、公開 GHCR artifact を digest 指定で取得し、
試験用 namespace 内の ConfigMap を選択同期できた。試験用リソースは削除した。

Longhorn は `home-k8s-app` の公開済み digest を指定して手動同期し、
Application が `Synced` / `Healthy` になることを確認した。テスト PVC を red から
green に付け替えて読み出しを確認し、検証用リソースを削除した。
