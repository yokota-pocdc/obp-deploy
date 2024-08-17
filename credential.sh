#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -euo pipefail

# ユーティリティスクリプトの読み込み
source ./utils.sh

# デフォルト値の設定
PROJECT_ID=""
REGION=""

# 引数の処理
while [[ $# -gt 0 ]]; do
  case $1 in
    --project-id=*)
      PROJECT_ID="${1#*=}"
      shift
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    *)
      handle_error 1 "Unknown argument: $1"
      ;;
  esac
done

# 必須パラメータの確認
validate_env_vars "PROJECT_ID" "REGION"

log $LOG_LEVEL_INFO "Project ID: $PROJECT_ID"
log $LOG_LEVEL_INFO "Region: $REGION"

# Secret Manager APIの有効化
log $LOG_LEVEL_INFO "Enabling Secret Manager API..."
enable_api "secretmanager.googleapis.com" "$PROJECT_ID"

# APIが有効化されたことを確認
log $LOG_LEVEL_INFO "Verifying Secret Manager API is enabled..."
API_ENABLED=$(gcloud services list --enabled --format="value(NAME)" --project=$PROJECT_ID | grep secretmanager.googleapis.com || true)
if [ -z "$API_ENABLED" ]; then
    handle_error 1 "Failed to enable Secret Manager API."
fi
log $LOG_LEVEL_INFO "Secret Manager API successfully enabled."

# シークレット名とJSONファイル名の設定
SECRET_NAME="add3-credential"
JSON_FILE="add3_credential.json"

# JSONファイルの存在確認
if [ ! -f "$JSON_FILE" ]; then
    handle_error 1 "$JSON_FILE not found."
fi

# シークレットの存在確認
if check_resource_exists "secrets" "$SECRET_NAME" "$PROJECT_ID"; then
    log $LOG_LEVEL_INFO "Secret '$SECRET_NAME' already exists. Adding a new version."
    # 新しいバージョンを追加
    gcloud secrets versions add $SECRET_NAME --data-file="$JSON_FILE" --project=$PROJECT_ID
    log $LOG_LEVEL_INFO "New version added to secret '$SECRET_NAME'."
else
    log $LOG_LEVEL_INFO "Creating new secret '$SECRET_NAME'..."
    # シークレットの作成と初期値の設定
    gcloud secrets create $SECRET_NAME --replication-policy="automatic" --data-file="$JSON_FILE" --project=$PROJECT_ID
    log $LOG_LEVEL_INFO "Secret '$SECRET_NAME' created and initial value set."
fi

log $LOG_LEVEL_INFO "Credential setup completed successfully."

# JSONファイルのクリーンアップ
log $LOG_LEVEL_INFO "Cleaning up sensitive files..."
shred -u "$JSON_FILE"
log $LOG_LEVEL_INFO "Sensitive files cleaned up."
