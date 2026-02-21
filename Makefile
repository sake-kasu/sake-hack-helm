ARGOCD_RELEASE ?= sake-hack-argocd
ARGOCD_NAMESPACE ?= sake-hack-ns
ARGOCD_CONTROL_PLANE_NAMESPACE ?= argocd
ARGOCD_CHART ?= argocd/
APP_NAMESPACE ?= sake-hack-ns
KUBECONFIG_FILE ?= $(abspath ./kubeconfig)
SOPS_AGE_KEY_FILE ?= $(abspath ./.local/sops/age/keys.txt)
BACKEND_SECRET_SAMPLE ?= backend/secrets/sake-hack-backend-secrets.dec.yaml.example
BACKEND_SECRET_DEC ?= backend/secrets/sake-hack-backend-secrets.dec.yaml
BACKEND_SECRET_ENC ?= backend/secrets/sake-hack-backend-secrets.enc.yaml

help:	## ヘルプ
	@awk 'BEGIN {FS = ":.*##"} /^([a-zA-Z0-9_-]+):.*##/ { printf "\033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

setup: ## asdfで必要なCLIを一括セットアップ
	@bash scripts/setup.sh

check-kubeconfig:
	@test -f "$(KUBECONFIG_FILE)" || (echo "❌ kubeconfig が見つかりません: $(KUBECONFIG_FILE)"; exit 1)

check-sops:
	@command -v sops >/dev/null 2>&1 || (echo "❌ sops が見つかりません"; exit 1)

check-age:
	@command -v age >/dev/null 2>&1 || (echo "❌ age が見つかりません"; exit 1)

check-sops-age-key:
	@test -f "$(SOPS_AGE_KEY_FILE)" || (echo "❌ age秘密鍵が見つかりません: $(SOPS_AGE_KEY_FILE)"; echo "   make backend-secrets-keygen を実行してください"; exit 1)

argocd-install: check-kubeconfig ## ArgoCD Applicationチャートをinstall
	@helm install $(ARGOCD_RELEASE) $(ARGOCD_CHART) --namespace $(ARGOCD_NAMESPACE) --kubeconfig $(KUBECONFIG_FILE)

argocd-upgrade: check-kubeconfig ## ArgoCD Applicationチャートをupgrade
	@helm upgrade $(ARGOCD_RELEASE) $(ARGOCD_CHART) --namespace $(ARGOCD_NAMESPACE) --kubeconfig $(KUBECONFIG_FILE)

argocd-uninstall: check-kubeconfig ## ArgoCD Applicationチャートをuninstall（確認あり）
	@printf "⚠️  $(ARGOCD_RELEASE) を $(ARGOCD_NAMESPACE) から削除します。実行しますか？ [y/N]: "; \
	read ans; \
	if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
		helm uninstall $(ARGOCD_RELEASE) --namespace $(ARGOCD_NAMESPACE) --kubeconfig $(KUBECONFIG_FILE); \
		echo "🗑️  uninstall を実行しました"; \
	else \
		echo "キャンセルしました"; \
		exit 1; \
	fi

status: check-kubeconfig ## ArgoCDとsake-hackの状態を確認
	@echo "📊 状態確認を開始します"
	@echo ""
	@echo "🧭 ArgoCD Applications ($(ARGOCD_NAMESPACE))"
	@kubectl --kubeconfig "$(KUBECONFIG_FILE)" -n "$(ARGOCD_NAMESPACE)" get applications 2>/dev/null || echo "⚠️  applications を参照できません（権限不足の可能性があります）"
	@echo ""
	@echo "🧩 ArgoCD Pods ($(ARGOCD_CONTROL_PLANE_NAMESPACE))"
	@kubectl --kubeconfig "$(KUBECONFIG_FILE)" -n "$(ARGOCD_CONTROL_PLANE_NAMESPACE)" get pods 2>/dev/null || echo "⚠️  pods を参照できません（権限不足の可能性があります）"
	@echo ""
	@echo "🚀 App Resources ($(APP_NAMESPACE))"
	@kubectl --kubeconfig "$(KUBECONFIG_FILE)" -n "$(APP_NAMESPACE)" get deploy,po,svc,ingress 2>/dev/null || echo "⚠️  app resources を参照できません（namespace/権限を確認してください）"

k9s: check-kubeconfig ## k9sをreadonlyで起動
	@k9s --kubeconfig $(KUBECONFIG_FILE) --readonly

k9s-rw: check-kubeconfig ## k9sを通常モードで起動
	@k9s --kubeconfig $(KUBECONFIG_FILE)

backend-secrets-keygen: check-age ## SOPS用age鍵をリポジトリ内に生成
	@mkdir -p "$(dir $(SOPS_AGE_KEY_FILE))"
	@if [ -f "$(SOPS_AGE_KEY_FILE)" ]; then \
		echo "ℹ️  age秘密鍵は既に存在します: $(SOPS_AGE_KEY_FILE)"; \
	else \
		age-keygen -o "$(SOPS_AGE_KEY_FILE)" >/dev/null; \
		echo "🔑 age秘密鍵を作成しました: $(SOPS_AGE_KEY_FILE)"; \
	fi
	@echo "📣 公開鍵: $$(awk '/public key:/ {print $$4; exit}' "$(SOPS_AGE_KEY_FILE)")"

backend-secrets-init: ## backend Secretの平文雛形を作成（未作成時のみ）
	@mkdir -p backend/secrets
	@if [ ! -f "$(BACKEND_SECRET_DEC)" ]; then \
		cp "$(BACKEND_SECRET_SAMPLE)" "$(BACKEND_SECRET_DEC)"; \
		echo "📝 $(BACKEND_SECRET_DEC) を作成しました"; \
	else \
		echo "ℹ️  $(BACKEND_SECRET_DEC) は既に存在します"; \
	fi

backend-secrets-encrypt: check-sops backend-secrets-init ## backend SecretをSOPSで暗号化
	@SOPS_AGE_KEY_FILE="$(SOPS_AGE_KEY_FILE)" sops --encrypt --output "$(BACKEND_SECRET_ENC)" "$(BACKEND_SECRET_DEC)"
	@echo "🔐 $(BACKEND_SECRET_ENC) を更新しました"

backend-secrets-decrypt: check-sops check-sops-age-key ## backend Secretを復号して平文ファイルを生成
	@test -f "$(BACKEND_SECRET_ENC)" || (echo "❌ 暗号化ファイルが見つかりません: $(BACKEND_SECRET_ENC)"; exit 1)
	@SOPS_AGE_KEY_FILE="$(SOPS_AGE_KEY_FILE)" sops --decrypt --output "$(BACKEND_SECRET_DEC)" "$(BACKEND_SECRET_ENC)"
	@echo "🔓 $(BACKEND_SECRET_DEC) を更新しました"

backend-secrets-apply: check-sops check-sops-age-key check-kubeconfig ## backend Secretを復号してクラスタへ適用
	@test -f "$(BACKEND_SECRET_ENC)" || (echo "❌ 暗号化ファイルが見つかりません: $(BACKEND_SECRET_ENC)"; exit 1)
	@SOPS_AGE_KEY_FILE="$(SOPS_AGE_KEY_FILE)" sops --decrypt "$(BACKEND_SECRET_ENC)" | kubectl --kubeconfig "$(KUBECONFIG_FILE)" apply -f -
	@echo "✅ backend Secretを適用しました"

.PHONY: help setup check-kubeconfig check-sops check-age check-sops-age-key argocd-install argocd-upgrade argocd-uninstall status k9s k9s-rw backend-secrets-keygen backend-secrets-init backend-secrets-encrypt backend-secrets-decrypt backend-secrets-apply
