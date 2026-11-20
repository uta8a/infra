# curatedz の人間作業

このディレクトリは設計・レビュー用であり、placeholder digestのまま適用しない。
適用は既存方針どおり、公開ファイルをOCI artifactへ梱包し、digest固定のArgo CD Applicationを人間が手動同期する。

1. curatedzのmainでRuntime images workflowを成功させ、summaryに出たsync/webのimage digestを`manifest.yaml`へ入れる。
2. AWSでS3の`state/v1/`、`batches/v1/`、`article-content/v1/`にGetObject/ListBucketだけを持つ同期専用IAM principalを作る。長期key以外の仕組みを採用できる場合は優先する。
3. `curatedz` namespaceを作り、`curatedz-aws` Secretへ`bucket`、`region`、`access-key-id`、`secret-access-key`を手元から作る。値をGitやshell historyへ残さない。
4. Cloudflare Zero TrustでTunnel、public hostname、self-hosted Access Application、本人だけを許可するPolicyを作る。詳細は「Cloudflare Access設定」を参照する。Tunnel serviceは`http://curatedz-web.curatedz.svc.cluster.local:80`とする。
5. `curatedz-cloudflare` Secretへ`team-domain`（例: `TEAM.cloudflareaccess.com`）、Application AUD、Tunnel tokenを手元から作る。
6. `manifest.yaml`と`application.example.yaml`の差分、PVC、resource、NetworkPolicyをレビューし、OCI digestを固定してArgo CDで手動syncする。OpenSearch、Web、syncの順に確認する。
7. 未認証のpublic hostnameと`/api/search`が拒否され、認証後のiPhone/PCから検索できることを確認する。ClusterIP以外にOpenSearch/Webの入口がないことも確認する。

再構築はsync imageを同じSecret/PVCで一時Jobとして起動し、引数`--rebuild`を付ける。新indexへの全投入成功後だけaliasが切り替わり、旧indexは自動削除しない。

## Cloudflare Access設定

Cloudflare側の設定値と本人のメールアドレスはprivateな運用情報として扱い、Gitへ保存しない。

1. Zero TrustのNetworks > Tunnelsでremote-managed Tunnelを作成する。
2. Tunnelへpublic hostnameを1件追加し、Serviceを`http://curatedz-web.curatedz.svc.cluster.local:80`にする。TLS検証無効化や外部originへの迂回は設定しない。
3. Access > Applicationsで同じhostnameを対象にSelf-hosted applicationを作成する。pathを限定せずhostname全体を保護する。
4. Allow policyはIncludeを`Emails`として本人のメールアドレス1件だけにする。`Everyone`、メールdomain全体、Bypass、Service Authは追加しない。
5. Login methodは自分が管理するIdPまたはOne-time PINだけを有効にする。セッション期間は初期値24時間以下とする。
6. ApplicationのAUD、team domain、Tunnel tokenを確認し、`curatedz-cloudflare` Secretの`audience`、`team-domain`、`tunnel-token`へそれぞれ設定する。

`curatedz-web`はCloudflare Accessのedge判定だけに依存せず、`Cf-Access-Jwt-Assertion`の署名、issuer、audience、有効期限を検証する。`curatedz-web` ServiceはClusterIPのままとし、Ingress、LoadBalancer、NodePortを追加しない。NetworkPolicyはcloudflared PodからWeb、Webとsync PodからOpenSearchへの通信だけを許可する。

## 外部公開の受け入れ確認

- シークレットウィンドウでpublic hostnameを開くと、ReaderではなくCloudflare Accessのログイン画面が表示される。
- 許可していないidentityではログインできない。
- 本人のidentityでは新着一覧と`/api/search`を利用できる。
- Access cookieを削除した後の`/`と`/api/search`はReaderの内容を返さない。
- cluster外からOpenSearchの9200番、Web Serviceの80/8080番へ直接接続できない。
- Pod内からJWT headerなしでWebへ直接要求した場合、`/`と`/api/search`はHTTP 401を返す。
- `/healthz`はKubernetes probe用であり、記事、URL、件数、設定値を返さない。
