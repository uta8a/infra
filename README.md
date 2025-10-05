# infra

My infrastructure configuration

Public Repository なので情報の扱いに気をつけてやる。

```txt
project-01/
    readme.yaml # サービスのメタデータ
```

## Environment

- prod: 本番環境
- stg: ステージング環境
- dev: 開発環境
- sandbox: 検証環境(prodへ取り込むつもりがあまりないもの)

<!-- BEGIN INFRA LIST -->
## Infrastructure Services

| Directory | Service Name | Platform | Environment | Deployed |
|-----------|--------------|----------|-------------|----------|
| home-k8s | home k8s | home-k8s | prod | ✓ |
| home-k8s-app | home k8s app | home-k8s | prod | ✓ |
| todo-app | Todo app | Google Cloud | sandbox | ✗ |
<!-- END INFRA LIST -->
