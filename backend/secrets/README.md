# backend secrets (SOPS + age)

1. `backend-secrets-init` で平文雛形を作成:
   - `make backend-secrets-init`
2. `backend/secrets/sake-hack-backend-secrets.dec.yaml` を編集
3. 暗号化:
   - `make backend-secrets-encrypt`
4. クラスタへ適用:
   - `make backend-secrets-apply`

前提:
- `sops` がインストール済み
- `.sops.yaml` の `age` 公開鍵を実値に更新済み
- `KUBECONFIG_FILE` が有効

## GHCR imagePullSecret (SOPS + age)

1. 平文生成（環境変数から作成）:
   - `GHCR_USERNAME=... GHCR_TOKEN=... GHCR_EMAIL=... make ghcr-pull-secret-from-env`
2. 暗号化:
   - `make ghcr-pull-secret-encrypt`
3. クラスタへ適用:
   - `make ghcr-pull-secret-apply`

補足:
- 平文は `backend/secrets/ghcr-pull-secret.dec.yaml`（`.gitignore`対象）
- 暗号化ファイルは `backend/secrets/ghcr-pull-secret.enc.yaml`
