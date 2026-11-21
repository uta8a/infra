# curatedz の人間作業

このディレクトリは設計・レビュー用であり、placeholder digestのまま適用しない。
適用は既存方針どおり、公開ファイルをOCI artifactへ梱包し、digest固定のArgo CD Applicationを人間が手動同期する。

1. curatedzのmainでRuntime images workflowを成功させ、summaryに出たsync/webのimage digestを`manifest.yaml`へ入れる。
2. AWS CloudFormationの`Curatedz` stackが`UPDATE_COMPLETE`で、`BucketName`、`SyncRoleArn`、`SyncTrustAnchorArn`、`SyncProfileArn`が`manifest.yaml`のConfigMapと一致することを確認する。同期Roleは対象S3 prefixのGetObject/ListBucketだけを持ち、IAM Userや長期Access Keyは使用しない。
3. Argo CD Applicationの初回手動syncで`curatedz` namespaceを作成する。作成を確認したら、`curatedz-aws` Secretへworkload証明書と秘密鍵だけを手元から投入する。CA秘密鍵、Access Key、STS credentialをKubernetes、Git、shell history、CIログへ残さない。詳細は「IAM Roles Anywhere設定」を参照する。
4. Cloudflare Zero TrustでTunnel、public hostname、self-hosted Access Application、本人だけを許可するPolicyを作る。詳細は「Cloudflare Access設定」を参照する。Tunnel serviceは`http://curatedz-web.curatedz.svc.cluster.local:80`とする。
5. `curatedz-cloudflare` Secretへ`team-domain`（例: `TEAM.cloudflareaccess.com`）、Application AUD、Tunnel tokenを手元から作る。
6. `manifest.yaml`と`application.example.yaml`の差分、PVC、resource、NetworkPolicyをレビューし、OCI digestを固定してArgo CDで手動syncする。OpenSearch、Web、syncの順に確認する。
7. 未認証のpublic hostnameと`/api/search`が拒否され、認証後のiPhone/PCから検索できることを確認する。ClusterIP以外にOpenSearch/Webの入口がないことも確認する。

再構築はsync imageを同じSecret/PVCで一時Jobとして起動し、引数`--rebuild`を付ける。新indexへの全投入成功後だけaliasが切り替わり、旧indexは自動削除しない。

## IAM Roles Anywhere設定

`curatedz-sync` imageにはchecksum固定の`/usr/local/bin/aws_signing_helper`が含まれる。Podは`curatedz-aws` ConfigMapの共有AWS configを`AWS_CONFIG_FILE`から読み、Secretとしてmountしたworkload証明書で有効期間1時間のSTS credentialを取得する。ConfigMapに記録するbucket、region、Trust Anchor/Profile/Role ARNは秘密情報ではないが、CloudFormation出力との不一致を防ぐためstack更新時に必ず再確認する。

現在のsync imageはAWS SDKのcredential INFOログを抑制したcuratedz main commit `7ded631`のRuntime images runで発行されたdigestへ固定している。`aws_signing_helper`を同梱していない旧digestではRoles Anywhere認証がexit 127で失敗し、credential INFOログを抑制していないdigestでは一時Access Key IDがログへ出るため、どちらにも戻さない。

証明書の秘密鍵はCA秘密鍵とは別にし、workload証明書のsubjectはAWS側の信頼条件と同じ`CN=curatedz-home-sync`とする。Git外のowner専用ディレクトリにある証明書を確認してから、管理端末で次を実行する。`HOME_SYNC_PKI_DIR`は実際の絶対パスへ置き換える。

```bash
openssl verify -CAfile HOME_SYNC_PKI_DIR/ca-cert.pem HOME_SYNC_PKI_DIR/workload-cert.pem
kubectl -n curatedz create secret generic curatedz-aws \
  --from-file=tls.crt=HOME_SYNC_PKI_DIR/workload-cert.pem \
  --from-file=tls.key=HOME_SYNC_PKI_DIR/workload-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -
```

Applicationの`CreateNamespace=true`により、初回手動sync時にArgo CDがdestination namespaceを作る。事前に管理端末からnamespaceを作成しない。SecretはOCI artifactへ含めず、namespaceの作成確認後、workload Podを正常化する前に投入する。

Secretのキーは`tls.crt`と`tls.key`の2件だけにする。`kubectl get secret ... -o yaml`や`describe`で値を表示せず、キー名だけを確認する。Secret volumeはread-onlyかつgroup-readableな`0440`でmountし、Podの`fsGroup: 65532`からだけ読めるようにする。

初回同期前にCronJobから一時Jobを作り、ログにAccess Key、証明書、署名済みリクエストが出ていないこと、Roles Anywhereからの認証とS3読み取りが成功することを確認する。証明書は期限前に新しい鍵で再発行し、Secret更新後の同期成功を確認してから旧証明書を廃止する。CA秘密鍵はオフライン保管し、漏えい時はCA、Trust Anchor、workload証明書を交換する。

## Cloudflare Access設定

Cloudflare側の設定値と本人のメールアドレスはprivateな運用情報として扱い、Gitへ保存しない。

1. Zero TrustのNetworks > Tunnelsでremote-managed Tunnelを作成する。
2. Tunnelへpublic hostnameを1件追加し、Serviceを`http://curatedz-web.curatedz.svc.cluster.local:80`にする。TLS検証無効化や外部originへの迂回は設定しない。
3. Access > Applicationsで同じhostnameを対象にSelf-hosted applicationを作成する。pathを限定せずhostname全体を保護する。
4. Allow policyはIncludeを`Login Methods: Passkeys`、Requireを`Emails`として本人のメールアドレス1件だけにする。`Everyone`、メールdomain全体、Bypass、Service Authは追加しない。
5. One-time PINなど別方式を併用する場合も、本人限定のRequire条件を外さない。セッション期間は初期値24時間以下とする。
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

## 適用状況

2026-11-22にhome-k8sへArgo CD経由で適用した。Applicationは`Synced`、`Healthy`、直近operationは`Succeeded`で、namespaceも`CreateNamespace=true`によりArgo CDが作成した。OpenSearch、Web、cloudflared、PVCは正常で、sync CronJobは15分周期で稼働している。

Roles Anywhereを使う検証Jobと再開後の定期Jobはともに成功した。表示前ログ検査ではAccess Key ID、秘密鍵、署名付きURL、Authorization headerのパターンは0件で、OpenSearchの`curatedz-articles` aliasから10件を検索対象として確認した。検証用Jobと、旧imageで失敗していたJobは削除済みである。
