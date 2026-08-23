# GitHub Actions から AWS Lambda Layer を Publish する設定

## 目的

GitHub Actions から AWS Lambda Layer を以下のコマンドで Publish できるようにする。

```bash
aws lambda publish-layer-version \
  --layer-name my-layer \
  --zip-file fileb://layer.zip
```

AWS の長期的な Access Key / Secret Access Key は GitHub Secrets に保存せず、GitHub Actions の OIDC を利用して IAM Role を Assume Role する。

構成は以下のとおり。

```text
GitHub Actions
     │
     │ OIDC
     ▼
GitHub OIDC Provider
     │
     │ AssumeRoleWithWebIdentity
     ▼
IAM Role
     │
     │ lambda:PublishLayerVersion
     ▼
AWS Lambda
     │
     ▼
Lambda Layer
```

---

## 1. 前提

以下を用意する。

* AWS アカウント
* GitHub リポジトリ
* AWS CLI を実行できる環境
* AWS IAM を設定できる権限
* Lambda Layer 用の ZIP ファイル

以降では、例として以下を使用する。

| 項目                       | 値                                     |
| ------------------------ | ------------------------------------- |
| AWS Account ID           | `123456789012`                        |
| AWS Region               | `ap-northeast-1`                      |
| GitHub Organization/User | `example-org`                         |
| GitHub Repository        | `my-lambda-layer`                     |
| GitHub Branch            | `main`                                |
| IAM Role                 | `GitHubActionsLambdaLayerPublishRole` |
| Lambda Layer             | `my-layer`                            |

実際の環境に合わせて置き換える。

---

# 2. AWS に GitHub OIDC Provider を登録する

GitHub Actions から AWS にアクセスするため、AWS IAM に GitHub の OIDC Provider を登録する。

AWS Management Console から、

**IAM → Identity providers → Add provider**

を開く。

以下を設定する。

### Provider type

```text
OpenID Connect
```

### Provider URL

```text
https://token.actions.githubusercontent.com
```

### Audience

```text
sts.amazonaws.com
```

登録する。

AWS の公式ドキュメントでも、この URL と Audience を使用する構成が案内されている。

> すでに GitHub Actions 用の OIDC Provider が AWS アカウントに存在する場合、この手順は不要。

---

# 3. GitHub Actions 用 IAM Role を作成する

IAM で、

**IAM → Roles → Create role**

を開く。

Trusted entity は、

```text
Web identity
```

を選択する。

Identity provider は先ほど作成した、

```text
token.actions.githubusercontent.com
```

を指定する。

Audience は、

```text
sts.amazonaws.com
```

を指定する。

Role name は例えば、

```text
GitHubActionsLambdaLayerPublishRole
```

とする。

---

# 4. IAM Role の Trust Policy を設定する

ここが重要。

GitHub Actions の OIDC Token を持っているだけで誰でもこの Role を Assume できる状態にはせず、**特定の GitHub Repository の `main` ブランチだけを許可する**。

Trust Policy を以下のように設定する。

![](img/trust-policy.png)

以下を自分の環境に変更する。

```text
123456789012
```

→ AWS Account ID

```text
example-org
```

→ GitHub Organization または User

```text
my-lambda-layer
```

→ GitHub Repository

GitHub の OIDC `sub` claim を Repository や Branch に限定することで、別の Repository からこの IAM Role を利用されることを防げる。GitHub も `sub` と `aud` による条件付けを推奨している。

### 注意

2026年7月15日以降に作成された Repository などでは、GitHub の immutable subject claim が使われる場合がある。

その場合は `sub` が、

```text
repo:example-org@123456/my-lambda-layer@456789:ref:refs/heads/main
```

のような形式になる。

自分の Repository でどの形式が使用されているかは GitHub の OIDC 設定を確認すること。

---

# 5. IAM Role に Lambda の Publish 権限を付与する

次に、この Role が Lambda Layer を Publish できるようにする。

IAM Role の Permissions に以下のポリシーを追加する。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublishLambdaLayer",
      "Effect": "Allow",
      "Action": [
        "lambda:PublishLayerVersion"
      ],
      "Resource": "arn:aws:lambda:ap-northeast-1:050478186852:layer:tf-gha-test-layer"
    }
  ]
}
```

これにより、

```text
tf-gha-test-layer
```

という Layer に対する Publish だけを許可する。

AWS の Lambda 用 IAM ポリシーでも `lambda:PublishLayerVersion` を Layer ARN に対して許可する構成が示されている。

---

# 6. Layer 名を限定しない場合

複数の Layer を GitHub Actions から Publish したい場合は、Resource をワイルドカードにできる。

例えば、

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublishLambdaLayers",
      "Effect": "Allow",
      "Action": [
        "lambda:PublishLayerVersion"
      ],
      "Resource": "arn:aws:lambda:ap-northeast-1:123456789012:layer:*"
    }
  ]
}
```

さらに Layer 名に Prefix を付けて、

```text
github-*
```

だけを許可することもできる。

```json
"Resource": "arn:aws:lambda:ap-northeast-1:123456789012:layer:github-*"
```

可能であれば、`*` よりもこのように対象を絞る。

---

# 7. GitHub Actions の Workflow を作成する

Repository に以下のファイルを作成する。

```text
.github/
└── workflows/
    └── publish-layer.yml
```

内容は以下。

```yaml
name: Publish Lambda Layer

on:
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  publish:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsLambdaLayerPublishRole
          aws-region: ap-northeast-1

      - name: Publish Lambda Layer
        run: |
          aws lambda publish-layer-version \
            --layer-name my-layer \
            --zip-file fileb://layer.zip \
            --compatible-runtimes python3.12 \
            --compatible-architectures arm64
```

AWS の GitHub Actions に関する公式例でも、`id-token: write` を付与し、`configure-aws-credentials` で IAM Role を Assume する構成になっている。

---

# 8. `layer.zip` を作成する

例えば Python Layer なら、Repository を以下のようにする。

```text
.
├── .github/
│   └── workflows/
│       └── publish-layer.yml
├── python/
│   └── my_package/
│       └── __init__.py
└── ...
```

Workflow で ZIP を作る。

```yaml
      - name: Build layer
        run: |
          zip -r layer.zip python/
```

その後 Publish する。

```yaml
      - name: Publish Lambda Layer
        run: |
          aws lambda publish-layer-version \
            --layer-name my-layer \
            --zip-file fileb://layer.zip \
            --compatible-runtimes python3.12 \
            --compatible-architectures arm64
```

最終的には、

```yaml
name: Publish Lambda Layer

on:
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  publish:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsLambdaLayerPublishRole
          aws-region: ap-northeast-1

      - name: Build layer
        run: |
          zip -r layer.zip python/

      - name: Publish Lambda Layer
        run: |
          aws lambda publish-layer-version \
            --layer-name my-layer \
            --zip-file fileb://layer.zip \
            --compatible-runtimes python3.12 \
            --compatible-architectures arm64
```

とする。

`PublishLayerVersion` は ZIP アーカイブから Layer を作成し、同じ Layer 名に対して Publish するたびに新しいバージョンを作成する。

---

# 9. GitHub に Push する

設定ができたら、

```bash
git add .github/workflows/publish-layer.yml
git commit -m "Add Lambda layer publishing workflow"
git push origin main
```

とする。

GitHub Actions が起動する。

---

# 10. GitHub Actions のログを確認する

GitHub Repository の、

```text
Actions
→ Publish Lambda Layer
```

を開く。

成功すれば、

```text
Configure AWS credentials
```

の Step で AWS Role の Assume Role に成功し、

```text
Publish Lambda Layer
```

で Lambda Layer が Publish される。

AWS CLI の結果には Layer Version が含まれる。

例えば、

```json
{
  "LayerArn": "arn:aws:lambda:ap-northeast-1:123456789012:layer:my-layer",
  "LayerVersionArn": "arn:aws:lambda:ap-northeast-1:123456789012:layer:my-layer:1",
  "Version": 1
}
```

---

# 11. Publish された Layer を確認する

AWS CLI から確認する場合、

```bash
aws lambda list-layer-versions \
  --layer-name my-layer \
  --region ap-northeast-1
```

または AWS Console の、

```text
Lambda
→ Layers
→ my-layer
```

から確認できる。

---

# 12. Layer Version ARN を後続処理で利用する

Layer を Publish したあと、その Version ARN を Lambda Function の設定などに利用する場合は、Workflow 内で結果を取得できる。

例えば、

```yaml
      - name: Publish Lambda Layer
        id: publish
        run: |
          LAYER_VERSION_ARN=$(aws lambda publish-layer-version \
            --layer-name my-layer \
            --zip-file fileb://layer.zip \
            --compatible-runtimes python3.12 \
            --compatible-architectures arm64 \
            --query 'LayerVersionArn' \
            --output text)

          echo "layer_version_arn=$LAYER_VERSION_ARN" >> "$GITHUB_OUTPUT"

      - name: Show Layer Version
        run: |
          echo "${{ steps.publish.outputs.layer_version_arn }}"
```

これで後続 Step から、

```text
${{ steps.publish.outputs.layer_version_arn }}
```

として参照できる。

例えば Lambda Function の更新まで行うなら、

```yaml
      - name: Update Lambda function
        run: |
          aws lambda update-function-configuration \
            --function-name my-function \
            --layers "${{ steps.publish.outputs.layer_version_arn }}"
```

のようにできる。

---

# 13. 推奨する最終構成

最初は以下くらいの構成にしておくとよい。

```text
GitHub
│
├── Repository
│   └── my-lambda-layer
│       │
│       ├── .github/
│       │   └── workflows/
│       │       └── publish-layer.yml
│       │
│       ├── python/
│       │   └── ...
│       │
│       └── ...
│
└── GitHub Actions
        │
        │ OIDC
        ▼
AWS IAM
│
├── OIDC Provider
│   └── token.actions.githubusercontent.com
│
└── Role
    └── GitHubActionsLambdaLayerPublishRole
        │
        └── Permission
            └── lambda:PublishLayerVersion
                    │
                    ▼
              AWS Lambda Layer
                    │
                    ├── Version 1
                    ├── Version 2
                    ├── Version 3
                    └── ...
```

---

# 14. セキュリティ上のポイント

## AWS Access Key を GitHub Secrets に保存しない

以下のような設定は、この用途では避ける。

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

を GitHub Secrets に保存して、

```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

とする方式ではなく、OIDC + IAM Role を使用する。

OIDC では GitHub Actions が AWS STS から一時的な認証情報を取得できるため、長期的な AWS Credential を管理する必要がない。

## Trust Policy を Repository / Branch に限定する

以下のように、

```json
"token.actions.githubusercontent.com:sub": "repo:example-org/my-lambda-layer:ref:refs/heads/main"
```

とする。

単純に、

```json
"token.actions.githubusercontent.com:sub": "*"
```

とするのは避ける。

## IAM Permission も最小限にする

今回必要なのは基本的に、

```json
"Action": [
  "lambda:PublishLayerVersion"
]
```

だけ。

Lambda Function の更新なども GitHub Actions から行うのであれば、その時点で別途、

```text
lambda:UpdateFunctionConfiguration
```

などを追加する。

最初から `AdministratorAccess` を付ける必要はない。

---

# 15. トラブルシューティング

## `Not authorized to perform sts:AssumeRoleWithWebIdentity`

まず IAM Role の Trust Policy を確認する。

特に、

```text
token.actions.githubusercontent.com:aud
```

が、

```text
sts.amazonaws.com
```

になっているか確認する。

また、

```text
token.actions.githubusercontent.com:sub
```

が GitHub Repository / Branch と一致しているか確認する。

---

## `Could not assume role with OIDC`

Workflow に以下があるか確認する。

```yaml
permissions:
  id-token: write
  contents: read
```

特に、

```yaml
id-token: write
```

が重要。

GitHub Actions が OIDC Token を取得するには、この permission が必要。

---

## `AccessDeniedException: lambda:PublishLayerVersion`

OIDC 自体は成功しているが、Assume した IAM Role に Lambda の Publish 権限がない可能性が高い。

以下を確認する。

```text
IAM
→ Roles
→ GitHubActionsLambdaLayerPublishRole
→ Permissions
```

そして、

```json
{
  "Effect": "Allow",
  "Action": "lambda:PublishLayerVersion",
  "Resource": "arn:aws:lambda:ap-northeast-1:123456789012:layer:my-layer"
}
```

が許可されているか確認する。

---

## `ResourceNotFoundException`

Layer ARN の Region が違っていないか確認する。

例えば、

```text
ap-northeast-1
```

で Publish しているのに、

```text
us-east-1
```

の Layer ARN を指定している、といったケース。

Workflow の、

```yaml
aws-region: ap-northeast-1
```

と CLI の実行先 Region が一致していることを確認する。

---

# 16. 参考資料

* [AWS Lambda — GitHub Actions を使用した Lambda デプロイ](https://docs.aws.amazon.com/lambda/latest/dg/deploying-github-actions.html?utm_source=chatgpt.com)
* [AWS Lambda — PublishLayerVersion API](https://docs.aws.amazon.com/lambda/latest/api/API_PublishLayerVersion.html?utm_source=chatgpt.com)
* [AWS IAM — OIDC federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html?utm_source=chatgpt.com)
* [GitHub — OpenID Connect reference](https://docs.github.com/en/actions/reference/security/oidc?utm_source=chatgpt.com)
