# sake-hack Helmチャート

このリポジトリは、sake-hackアプリケーション（backend/frontend）をKubernetesにデプロイするためのHelmチャートを管理します。ArgoCDによるGitOps方式での自動デプロイをサポートしています。

## リポジトリ構造

```
sake-hack-helm/
├── backend/                     # バックエンド用Helmチャート
│   ├── Chart.yaml              # チャートメタデータ
│   ├── values.yaml             # 設定値
│   ├── secrets/                # backend Secret管理（SOPS + age）
│   │   └── *.enc.yaml
│   └── templates/              # Kubernetesマニフェストテンプレート
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── configmap.yaml
│       ├── secret.yaml
│       └── hpa.yaml
├── frontend/                    # フロントエンド用Helmチャート
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       └── (backend/と同様)
├── argocd/                      # ArgoCD Application用 Helmチャート
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       └── applications.yaml
├── external-services/            # クラスター外のStatefulサービス用Compose
│   ├── compose.yaml
│   └── .env.sample
└── README.md                    # このファイル
```

## 前提条件

- Kubernetes 1.19以上
- Helm 3.0以上
- NGINX Ingress Controller
- cert-manager（自動TLS証明書プロビジョニング用）
- ArgoCD（GitOpsデプロイ用）
- asdf（CLIバージョン管理用）
- sops（Secret暗号化用）
- age（sops鍵管理用）

## 初期セットアップ（asdf）

このリポジトリは`.tool-versions`で`age`/`argocd`/`helm`/`kubectl`/`sops`のバージョンを固定しています。  
初回セットアップは以下を実行してください。

```bash
make setup
```

`make setup`は以下をまとめて実行します:

1. `.tool-versions`に記載されたツールのasdfプラグイン追加
2. 指定バージョンのインストール
3. `asdf reshim`

## クラスター外Statefulサービスの起動（自宅サーバー）

PostgreSQL / Valkey / RustFSをクラスター外（例: `192.168.0.140`）に置く場合は、`external-services/compose.yaml` を使えます。

```bash
cd external-services
cp .env.sample .env
vim .env
docker compose up -d
```

backend側の接続先設定（`backend/values.yaml`）は以下を想定しています。

- `DB_HOST=192.168.0.140`
- `CACHE_HOST=192.168.0.140`
- `STORAGE_ENDPOINT=https://storage.sake-hack.com`

RustFSのCORSについて:

- Presigned URLを実際に叩くのはブラウザなので、**本番は `https://web.sake-hack.com` のみ許可**で問題ありません。
- backend -> RustFS のサーバー間通信にはCORSは関係ありません。
- ローカル開発でブラウザから直接RustFSを叩く場合のみ、`http://localhost:5173` などを追加してください。

## イメージタグ自動更新CI（Argo CD自動反映用）

`targetRevision: main`のまま自動デプロイするために、`image.tag`を自動更新するCIを用意しています。

- ワークフロー: `.github/workflows/update-image-tags.yml`
- 更新対象:
  - `backend/values.yaml` の `image.tag`
  - `frontend/values.yaml` の `image.tag`

このワークフローは以下で起動できます:

1. このリポジトリで手動実行（`workflow_dispatch`）
2. backend/frontendリポジトリから`repository_dispatch`

### backend/frontendリポジトリからのトリガ

backend/frontend側のCIで、イメージpush後にこのリポジトリへ`repository_dispatch`を送ると、`main`のタグが更新されます。

必要な設定:

1. このHelmリポジトリに`repo`権限を持つPATを作成
2. backend/frontendリポジトリのSecretsに`HELM_REPO_DISPATCH_TOKEN`として登録

backend側の送信例:

```bash
curl -L -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${HELM_REPO_DISPATCH_TOKEN}" \
  https://api.github.com/repos/sake-kasu/sake-hack-helm/dispatches \
  -d '{"event_type":"backend-image-pushed","client_payload":{"service":"backend","tag":"git-'"${GITHUB_SHA}"'"}}'
```

frontend側の送信例:

```bash
curl -L -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${HELM_REPO_DISPATCH_TOKEN}" \
  https://api.github.com/repos/sake-kasu/sake-hack-helm/dispatches \
  -d '{"event_type":"frontend-image-pushed","client_payload":{"service":"frontend","tag":"git-'"${GITHUB_SHA}"'"}}'
```

## デプロイされるアプリケーション

### Backend
- **イメージ**: `ghcr.io/sake-kasu/sake-hack-backend:<tag>`
- **タグ運用**: 初期値は`latest`。通常はCIが`git-<commit-sha>`へ自動更新
- **ドメイン**: `api.sake-hack.com`
- **namespace**: `sake-hack-ns`

### Frontend
- **イメージ**: `ghcr.io/sake-kasu/sake-hack-frontend:<tag>`
- **タグ運用**: 初期値は`latest`。通常はCIが`git-<commit-sha>`へ自動更新
- **ドメイン**: `web.sake-hack.com`
- **namespace**: `sake-hack-ns`

## ArgoCD自動デプロイの設定

### 0. backend Secretの適用（初回または更新時）

```bash
make backend-secrets-apply
```

### 0.5 GHCRのimagePullSecret適用（private package運用時）

```bash
GHCR_USERNAME=<github-username> \
GHCR_TOKEN=<github-pat-or-fine-grained-token> \
GHCR_EMAIL=<email> \
make ghcr-pull-secret-from-env

make ghcr-pull-secret-encrypt
make ghcr-pull-secret-apply
```

- 平文: `backend/secrets/ghcr-pull-secret.dec.yaml`（`.gitignore`対象）
- 暗号化: `backend/secrets/ghcr-pull-secret.enc.yaml`

### 1. ArgoCD Applicationの適用

```bash
# ArgoCD ApplicationsをHelmで適用
helm upgrade --install sake-hack-argocd argocd/ \
  --namespace sake-hack-ns
```

### 2. 自動同期の動作

mainブランチへのpush時、ArgoCDが自動的に以下を実行します:
- 変更の検知
- Helmチャートのレンダリング
- Kubernetesリソースの同期
- 手動変更の自動修正（selfHeal）
- 削除されたリソースのクリーンアップ（prune）

### 3. デプロイ状態の確認

```bash
# ArgoCD Applicationの状態確認
kubectl get applications -n sake-hack-ns

# 詳細確認
kubectl get application sake-hack-backend -n sake-hack-ns -o yaml
kubectl get application sake-hack-frontend -n sake-hack-ns -o yaml

# sake-hack-ns namespaceのリソース確認
kubectl get all -n sake-hack-ns
```

### 4. ArgoCD UIでの確認

ArgoCD UIにアクセスして視覚的に確認できます:
- URL: `http://<your-argocd-server>` (例: `http://192.168.0.200:30180`)
- ユーザー名: `admin`
- 初期パスワード取得:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  ```

## 手動デプロイ（ArgoCD不使用の場合）

ArgoCDを使わずに直接デプロイする場合:

### Backend

```bash
helm install sake-hack-backend backend/ \
  --namespace sake-hack-ns \
  --create-namespace
```

### Frontend

```bash
helm install sake-hack-frontend frontend/ \
  --namespace sake-hack-ns \
  --create-namespace
```

## アップグレード

### ArgoCD経由（推奨）

GitリポジトリのmainブランチにHelmチャートの変更をpushするだけで自動的にデプロイされます。

```bash
# values.yamlを編集
vim backend/values.yaml

# コミット＆プッシュ
git add backend/values.yaml
git commit -m "Update backend configuration"
git push origin main

# ArgoCDが自動的に同期（数分以内）
```

### 手動アップグレード

```bash
helm upgrade sake-hack-backend backend/ --namespace sake-hack-ns
helm upgrade sake-hack-frontend frontend/ --namespace sake-hack-ns
```

## アンインストール

### ArgoCD Application削除

```bash
helm uninstall sake-hack-argocd --namespace sake-hack-ns
```

### 手動削除

```bash
helm uninstall sake-hack-backend --namespace sake-hack-ns
helm uninstall sake-hack-frontend --namespace sake-hack-ns
```

## 設定のカスタマイズ

各アプリケーションの`values.yaml`を編集して設定をカスタマイズできます。

### 主要パラメータ

| パラメータ | 説明 | デフォルト値 |
|-----------|------|-------------|
| `replicaCount` | レプリカ数 | `2` |
| `image.repository` | イメージリポジトリ | backend: `ghcr.io/sake-kasu/sake-hack-backend`<br>frontend: `ghcr.io/sake-kasu/sake-hack-frontend` |
| `image.tag` | イメージタグ | 初期値: `latest`（CIで `git-<commit-sha>` に更新） |
| `service.targetPort` | コンテナポート | `8080` |
| `ingress.hosts` | Ingressホスト | backend: `api.sake-hack.com`<br>frontend: `web.sake-hack.com` |
| `resources.limits.cpu` | CPU制限 | `500m` |
| `resources.limits.memory` | メモリ制限 | `512Mi` |
| `autoscaling.enabled` | HPAを有効化 | `false` |

### Secretsの管理

backend は `SOPS + age` で暗号化Secretを管理します。

1. age鍵ペアを生成（リポジトリ内・gitignore対象）
   ```bash
   make backend-secrets-keygen
   ```
2. 生成された公開鍵（`age1...`）を `.sops.yaml` の `age` に設定
   - 公開鍵確認例:
     ```bash
     awk '/public key:/ {print $4; exit}' .local/sops/age/keys.txt
     ```
3. 平文雛形を作成
   ```bash
   make backend-secrets-init
   ```
4. `backend/secrets/sake-hack-backend-secrets.dec.yaml` を編集
5. 暗号化ファイルを生成
   ```bash
   make backend-secrets-encrypt
   ```
6. クラスタへ適用
   ```bash
   make backend-secrets-apply
   ```

運用上のポイント:

- backendチャートはデフォルトで `secrets.enabled=false` です
- Deploymentは既存Secret `sake-hack-backend-secrets` を参照します
- `*.dec.yaml`（平文）は `.gitignore` で除外し、コミットしません
- age秘密鍵は `.local/sops/age/keys.txt` を使用し、`.gitignore`で除外します

## DNS設定

以下のドメインをクラスターのIngress IPに向ける必要があります:

```
api.sake-hack.com  → <Ingress LoadBalancer IP>
web.sake-hack.com  → <Ingress LoadBalancer IP>
```

Ingress IPの確認:
```bash
kubectl get svc -n ingress-nginx
```

## トラブルシューティング

### Podが起動しない場合

```bash
# Pod状態確認
kubectl get pods -n sake-hack-ns

# ログ確認
kubectl logs -n sake-hack-ns -l app.kubernetes.io/name=sake-hack-backend
kubectl logs -n sake-hack-ns -l app.kubernetes.io/name=sake-hack-frontend

# イベント確認
kubectl get events -n sake-hack-ns --sort-by='.lastTimestamp'
```

### ArgoCD同期エラー

```bash
# Application詳細確認
kubectl describe application sake-hack-backend -n argocd

# ArgoCD UIで詳細なエラーメッセージを確認
```

### Helmチャートの検証

```bash
# lintチェック
helm lint backend/
helm lint frontend/

# dry-runでレンダリング確認
helm template sake-hack-backend backend/ --debug
helm template sake-hack-frontend frontend/ --debug
```

## ベストプラクティス

1. **GitOps**: ArgoCD経由での自動デプロイを推奨
2. **Secrets管理**: 機密情報はGitにコミットせず、Sealed Secretsなどを使用
3. **イメージタグ**: 本番環境では`latest`ではなく固定バージョンを使用
4. **リソース制限**: 本番環境では必ずリソース制限を設定
5. **TLS証明書**: cert-managerとLet's Encryptを使用して自動化
6. **モニタリング**: Prometheus/Grafanaなどでメトリクス監視を推奨

## ライセンス

詳細は[LICENSE](./LICENSE)ファイルを参照してください。
