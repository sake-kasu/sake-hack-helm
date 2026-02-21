#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOL_VERSIONS_FILE="${REPO_ROOT}/.tool-versions"

echo "🚀 sake-hack-helm のセットアップを開始します"

if ! command -v asdf >/dev/null 2>&1; then
  echo "❌ asdf がインストールされていません。先に asdf をインストールしてください: https://asdf-vm.com/"
  exit 1
fi

if [[ ! -f "${TOOL_VERSIONS_FILE}" ]]; then
  echo "❌ .tool-versions が見つかりません: ${TOOL_VERSIONS_FILE}"
  exit 1
fi

echo "📄 ${TOOL_VERSIONS_FILE} の設定を使用します"

while IFS=' ' read -r plugin version _; do
  if [[ -z "${plugin}" || "${plugin:0:1}" == "#" ]]; then
    continue
  fi

  if asdf plugin list | grep -qx "${plugin}"; then
    echo "✅ asdf プラグイン '${plugin}' は追加済みです"
  else
    echo "📦 asdf プラグイン '${plugin}' を追加します"
    asdf plugin add "${plugin}"
  fi

  echo "⬇️  ${plugin} ${version} をインストールします"
  asdf install "${plugin}" "${version}"
  echo "✅ ${plugin} ${version} をインストールしました"
done < "${TOOL_VERSIONS_FILE}"

echo "🔁 asdf reshim を実行します"
asdf reshim

echo "🔍 インストール済みバージョンを確認します"
while IFS=' ' read -r plugin version _; do
  if [[ -z "${plugin}" || "${plugin:0:1}" == "#" ]]; then
    continue
  fi

  if asdf where "${plugin}" "${version}" >/dev/null 2>&1; then
    echo "✅ ${plugin} ${version} の準備ができました"
  else
    echo "⚠️  ${plugin} ${version} がインストール後に見つかりませんでした"
  fi
done < "${TOOL_VERSIONS_FILE}"

echo "🎉 セットアップが完了しました"
