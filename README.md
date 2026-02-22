# sake-hack Helmチャート

このリポジトリは、sake-hackアプリケーション（backend/frontend）を Kubernetes (K8s: Kubernetes) にデプロイするための Helm チャートを管理します。Argo CD (Argo Continuous Delivery) による GitOps (Git-based Operations) 方式の自動デプロイをサポートしています。

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
- Argo CD (Argo Continuous Delivery)（GitOpsデプロイ用）
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

## インフラ構成

このセクションは、sake-hack を動かすための全体構成を「インフラ担当でないエンジニアにも追いやすい形」でまとめたものです。

### 全体像

- アプリ本体（Frontend / Backend）は Kubernetes クラスター上に配置
- データを持つサービス（PostgreSQL / Valkey / RustFS）はクラスター外の自宅サーバーに配置
- 公開ドメイン（`web.sake-hack.com` / `api.sake-hack.com` / `storage.sake-hack.com`）は Ingress (Kubernetes Ingress) 経由で公開
- TLS (Transport Layer Security) 証明書は cert-manager + Let's Encrypt で自動発行（Issuer名: `sake-hack-letsencrypt`）
- `*.sake-hack.com` の DDNS (Dynamic DNS) 更新は、別管理の Kubernetes クラスター上の CronJob (定期実行ジョブ) で実行

補足:
- 別管理クラスター側の具体的な名前は、この README では `master-namespace` / `master-argocd-namespace` としてぼかして記載します（sake-hack 本体とは直接関係しないため）。

### Kubernetes クラスター（sake-hack 配置先）

- 構築方式: Kubespray
- ノード数: 3台
- ノード名: `node1`, `node2`, `node3`
- ハードウェア構成:
  - Raspberry Pi 4B
  - Raspberry Pi 5 (8GB)
  - Raspberry Pi 5 (16GB)
- OS: Ubuntu 24 LTS（全ノード）
- 自動更新: 無効

IP / ネットワーク方針:

- ノードIPはルーター側で MAC アドレス指定の DHCP (Dynamic Host Configuration Protocol) 予約で固定
- 過去に `netplan` による固定設定が壊れることがあったため、現在はルーター側固定を採用
- ノードIP:
  - `node1`: `192.168.0.200`
  - `node2`: `192.168.0.201`
  - `node3`: `192.168.0.202`
- Ingress 用の VIP (Virtual IP): `192.168.0.100`（MetalLB が払い出し）
- ISP 都合により IPv6 は未使用（IPv4 前提）

ルーターのポートフォワード（公開用）:

- `80/tcp` -> `192.168.0.200:30080`
- `443/tcp` -> `192.168.0.200:30443`

### クラスター内に置くもの / 置かないもの

クラスター内（Kubernetes）:

- Frontend（Webアプリ）
- Backend（APIサーバー）
- Argo CD（GitOpsデプロイ制御）
- cert-manager（証明書管理）

クラスター外（自宅サーバー, `192.168.0.140`）:

- PostgreSQL（データベース）
- Valkey（キャッシュ）
- RustFS（S3互換オブジェクトストレージ）

この構成の意図:

- Kubernetes 側をできるだけ stateless (状態を持たない) に保つ
- データ永続化をクラスター外の 1 台に寄せる

### クラスター外サーバー（Stateful サービス配置先）

- IP: `192.168.0.140`
- CPUアーキテクチャ: `amd64`
- OS: Ubuntu 24 LTS
- 起動方式: Docker Compose（常駐）

使用ポート（このリポジトリの想定値）:

- PostgreSQL: `5454`
- Valkey: `6397`
- RustFS API: `9191`
- RustFS Console: `9001`（ローカルアクセス前提）

### ドメイン / DDNS / 証明書の役割分担

- `web.sake-hack.com` -> Frontend
- `api.sake-hack.com` -> Backend
- `storage.sake-hack.com` -> RustFS（クラスター外サーバーを Ingress 経由で公開）
- `*.sake-hack.com` の DDNS 更新は、別管理クラスターの `master-namespace` 上の CronJob で実行
  - ワイルドカード 1 件を更新
  - 定期実行で公開 IPv4 の変化に追従

## 初回構築（Helm / Argo CD まで）

この手順は「sake-hack の Helm チャートをデプロイ可能な状態にするところまで」を対象にしています。  
（DBマイグレーション、バケット作成、アプリの動作確認は別手順）

1. CLIツールをセットアップ（asdf）

```bash
make setup
```

2. `kubeconfig` をこのリポジトリ直下に配置（`./kubeconfig`）

3. backend Secret を適用（SOPS + age）

```bash
make backend-secrets-apply
```

4. GHCR (GitHub Container Registry) の imagePullSecret を使う場合は適用

```bash
make ghcr-pull-secret-apply
```

5. Argo CD Application（sake-hack 用の Application リソース）をインストール

```bash
make argocd-install
```

6. 状態確認

```bash
make status
```

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

RustFSの CORS (Cross-Origin Resource Sharing) について:

- Presigned URLを実際に叩くのはブラウザなので、**本番は `https://web.sake-hack.com` のみ許可**で問題ありません。
- backend -> RustFS のサーバー間通信にはCORSは関係ありません。
- ローカル開発でブラウザから直接RustFSを叩く場合のみ、`http://localhost:5173` などを追加してください。

## イメージタグ自動更新CI（CI: Continuous Integration / Argo CD自動反映用）

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

1. このHelmリポジトリに`repo`権限を持つ PAT (Personal Access Token) を作成
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
- **タグ運用**: 通常は CI が `git-<commit-sha>` 形式へ更新（固定タグ運用）
- **ドメイン**: `api.sake-hack.com`
- **namespace**: `sake-hack-ns`

### Frontend
- **イメージ**: `ghcr.io/sake-kasu/sake-hack-frontend:<tag>`
- **タグ運用**: 通常は CI が `git-<commit-sha>` 形式へ更新（固定タグ運用）
- **ドメイン**: `web.sake-hack.com`
- **namespace**: `sake-hack-ns`

## ArgoCD自動デプロイの設定

### 0. backend Secretの適用（初回または更新時）

```bash
make backend-secrets-apply
```

### 0.5 GHCR (GitHub Container Registry) のimagePullSecret適用（private package運用時）

```bash
# 平文ひな形を作成（未作成時）
cp backend/secrets/ghcr-pull-secret.dec.yaml.example \
  backend/secrets/ghcr-pull-secret.dec.yaml

# backend/secrets/ghcr-pull-secret.dec.yaml を編集
vim backend/secrets/ghcr-pull-secret.dec.yaml

make ghcr-pull-secret-encrypt
make ghcr-pull-secret-apply
```

- 平文: `backend/secrets/ghcr-pull-secret.dec.yaml`（`.gitignore`対象）
- 暗号化: `backend/secrets/ghcr-pull-secret.enc.yaml`

### 1. ArgoCD Applicationの適用

```bash
# 初回
make argocd-install

# 変更反映時
make argocd-upgrade
```

- `argocd/` チャートが作成するのは Argo CD の Application リソース（`sake-hack-ns`）です
- Argo CD のコントロールプレーン（実体の Pod 群）は通常 `argocd` namespace にあります

### 2. 自動同期の動作

mainブランチへのpush時、ArgoCDが自動的に以下を実行します:
- 変更の検知
- Helmチャートのレンダリング
- Kubernetesリソースの同期
- 手動変更の自動修正（selfHeal）
- 削除されたリソースの自動削除はしない（prune=false）

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
| `image.tag` | イメージタグ | `git-<commit-sha>`（CIで更新） |
| `service.targetPort` | コンテナポート | `8080` |
| `ingress.hosts` | Ingressホスト | backend: `api.sake-hack.com`<br>frontend: `web.sake-hack.com` |
| `resources.limits.cpu` | CPU制限 | `500m` |
| `resources.limits.memory` | メモリ制限 | `512Mi` |
| `autoscaling.enabled` | HPAを有効化 | `false` |

### Secretsの管理

このリポジトリでは、主に backend Secret と GHCR の imagePullSecret を `SOPS (Secrets OPerationS) + age` で管理します。

#### age秘密鍵の配置場所

- age 秘密鍵ファイル（ローカルのみ、Git 管理しない）:
  - `.local/sops/age/keys.txt`
- `Makefile` の既定値（`SOPS_AGE_KEY_FILE`）もこのパスを参照します

#### 復号できるメンバーの初期手順（鍵をまだ持っていない場合）

1. age 鍵ペアを生成（ローカル）
   ```bash
   make backend-secrets-keygen
   ```
2. 公開鍵（`age1...`）を既に復号できるメンバーへ共有
   ```bash
   awk '/public key:/ {print $4; exit}' .local/sops/age/keys.txt
   ```
3. 既存メンバーに対応してもらう内容
   - `.sops.yaml` に新しい公開鍵を追加
   - 暗号化済み Secret（`*.enc.yaml`）を再暗号化してコミット
4. そのコミットを取り込んだ後、自分の環境で復号
   ```bash
   make backend-secrets-decrypt
   make ghcr-pull-secret-decrypt
   ```

補足:
- **新規メンバーだけでは既存の暗号化ファイルを復号できません。** 必ず「既に復号できるメンバー」の対応が必要です。

#### backend Secret の編集〜適用

1. 平文雛形を作成（未作成時のみ）
   ```bash
   make backend-secrets-init
   ```
2. 平文ファイルを編集
   - `backend/secrets/sake-hack-backend-secrets.dec.yaml`
3. 暗号化ファイルを更新
   ```bash
   make backend-secrets-encrypt
   ```
4. クラスタへ適用
   ```bash
   make backend-secrets-apply
   ```

#### GHCR (GitHub Container Registry) imagePullSecret の編集〜適用

1. 平文雛形をコピー（未作成時のみ）
   ```bash
   cp backend/secrets/ghcr-pull-secret.dec.yaml.example \
     backend/secrets/ghcr-pull-secret.dec.yaml
   ```
2. 平文ファイルを編集
   - `backend/secrets/ghcr-pull-secret.dec.yaml`
3. 暗号化ファイルを更新
   ```bash
   make ghcr-pull-secret-encrypt
   ```
4. クラスタへ適用
   ```bash
   make ghcr-pull-secret-apply
   ```

運用上のポイント:

- backend チャートはデフォルトで `secrets.enabled=false` です
- Deployment は既存 Secret `sake-hack-backend-secrets` を参照します
- `*.dec.yaml`（平文）は `.gitignore` で除外し、コミットしません
- age 秘密鍵（`.local/sops/age/keys.txt`）も `.gitignore` で除外し、コミットしません

## DNS設定

### Aレコード（公開先）

以下のドメインを Ingress の VIP (Virtual IP) `192.168.0.100` に向けます。

```text
api.sake-hack.com      -> 192.168.0.100
web.sake-hack.com      -> 192.168.0.100
storage.sake-hack.com  -> 192.168.0.100
```

補足:
- `storage.sake-hack.com` はクラスター外の RustFS を、Kubernetes Ingress 経由で公開するためのホスト名です。

### DDNS（Dynamic DNS）運用

- `*.sake-hack.com` の更新は、別管理 Kubernetes クラスターの `master-namespace` にある CronJob で実行しています
- DDNS 更新ジョブはワイルドカード 1 件を定期更新します
- DDNS 更新ジョブは `backoffLimit: 0`（失敗時の自動再試行なし）で運用しています
- この README では、別管理クラスター側の詳細 namespace は `master-namespace` / `master-argocd-namespace` として記載します

### ルーター設定（公開ポート）

```text
80/tcp   -> 192.168.0.200:30080
443/tcp  -> 192.168.0.200:30443
```

Ingress VIP の確認（参考）:
```bash
kubectl get svc -A | grep LoadBalancer
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
# Application詳細確認（Applicationリソースは sake-hack-ns に存在）
kubectl describe application sake-hack-backend -n sake-hack-ns

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

## 用語メモ（初心者向け）

- Kubernetes (K8s: Kubernetes): コンテナ化したアプリを複数サーバーで動かしやすくする基盤
- Helm: Kubernetes 向けの設定テンプレート（チャート）を扱うツール
- Argo CD (Argo Continuous Delivery): Git の内容を Kubernetes に反映する GitOps ツール
- GitOps (Git-based Operations): Git を正本（source of truth）として運用する方法
- Ingress (Kubernetes Ingress): HTTP/HTTPS の入り口（どのホスト名をどのサービスに流すか決める）
- VIP (Virtual IP): 複数ノードの前段で使う仮想IP（ここでは MetalLB が払い出す公開先IP）
- cert-manager: TLS 証明書の発行・更新を Kubernetes 上で自動化するコンポーネント
- DDNS (Dynamic DNS): 変動するグローバルIPに対して DNS レコードを自動更新する仕組み
- SOPS (Secrets OPerationS): Secret を暗号化して Git 管理しやすくするツール
- age: SOPS で使うシンプルな鍵暗号方式（このリポジトリでは Secret 暗号化に使用）

## ベストプラクティス

1. **GitOps**: ArgoCD経由での自動デプロイを推奨
2. **Secrets管理**: 機密情報は平文をGitにコミットせず、`SOPS + age` で暗号化して管理
3. **イメージタグ**: 本番環境では`latest`ではなく固定バージョンを使用
4. **リソース制限**: 本番環境では必ずリソース制限を設定
5. **TLS証明書**: cert-managerとLet's Encryptを使用して自動化
6. **モニタリング**: Prometheus/Grafanaなどでメトリクス監視を推奨

## ライセンス

詳細は[LICENSE](./LICENSE)ファイルを参照してください。
