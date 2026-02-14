# terraform-backend

Terraform backend 用の AWS リソースを CDK で作成します。

- S3: Terraform state 保存
- S3 conditional write: Terraform lock

## Prerequisites

- Node.js
- pnpm
- AWS credential が設定済み
- デプロイ先リージョンを環境変数で指定

```bash
export CDK_DEFAULT_REGION=ap-northeast-1
```

## Deploy

```bash
pnpm install
pnpm run deploy
```

## Terraform backend example

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-<account-id>-<region>"
    key          = "global/terraform.tfstate"
    region       = "<region>"
    use_lockfile = true # S3 conditional write を使用してロックを実装
    encrypt      = true
  }
}
```
