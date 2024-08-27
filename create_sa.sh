#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -euo pipefail

# ユーティリティスクリプトの読み込み
source ./utils.sh

# デフォルト値の設定
PROJECT_ID=""
REGION=""
SERVICE_ACCOUNT_NAME=""

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
    --service-account-name=*)
      SERVICE_ACCOUNT_NAME="${1#*=}"
      shift
      ;;
    *)
      handle_error 1 "Unknown argument: $1"
      ;;
  esac
done

# 必須パラメータの確認
validate_env_vars "PROJECT_ID" "REGION" "SERVICE_ACCOUNT_NAME"

log $LOG_LEVEL_INFO "Project ID: $PROJECT_ID"
log $LOG_LEVEL_INFO "Region: $REGION"
log $LOG_LEVEL_INFO "Service Account Name: $SERVICE_ACCOUNT_NAME"

# サービスアカウントの設定
SERVICE_ACCOUNT_DISPLAY_NAME="OBP Deployment Service Account"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
log $LOG_LEVEL_INFO "Creating or updating service account: $SERVICE_ACCOUNT_EMAIL"

# サービスアカウントの存在確認
if check_resource_exists "iam service-accounts" "$SERVICE_ACCOUNT_EMAIL" "$PROJECT_ID"; then
    log $LOG_LEVEL_INFO "Service account $SERVICE_ACCOUNT_EMAIL already exists."
else
    log $LOG_LEVEL_INFO "Creating service account $SERVICE_ACCOUNT_EMAIL"
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="$SERVICE_ACCOUNT_DISPLAY_NAME" \
        --project=$PROJECT_ID
    log $LOG_LEVEL_INFO "Service account $SERVICE_ACCOUNT_EMAIL has been created."
    
    # 必要な役割を付与
    log $LOG_LEVEL_INFO "Granting necessary roles to the service account."

    roles=(
	    "roles/artifactregistry.repoAdmin"
	    "roles/artifactregistry.admin"
	    "roles/artifactregistry.writer"
	    "roles/artifactregistry.reader"
	    "roles/bigquery.jobUser"
	    "roles/bigquery.dataViewer"
	    "roles/bigquery.dataEditor"
	    "roles/bigquery.readSessionUser"
	    "roles/bigquery.admin"
	    "roles/bigquerydatatransfer.serviceAgent"
	    "roles/containerregistry.ServiceAgent"
	    "roles/dataflow.developer"
	    "roles/dataflow.worker"
	    "roles/dataflow.admin"  # Dataflow管理者権限を追加
	    "roles/storage.admin"
	    "roles/storage.objectViewer"
	    "roles/storage.objectAdmin"
	    "roles/storage.objectCreator"
	    "roles/iam.serviceAccountUser"
	    "roles/iam.serviceAccountTokenCreator"  # サービスアカウントトークン作成権限を追加
	    "roles/serviceusage.serviceUsageAdmin"
            "roles/cloudbuild.builds.viewer"
	    "roles/serviceusage.serviceUsageConsumer"
    )
    for role in "${roles[@]}"
    do
        if ! gcloud projects add-iam-policy-binding $PROJECT_ID \
            --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
            --role="$role"; then
            log $LOG_LEVEL_WARN "Failed to add role $role. Continuing with other roles."
        else
            log $LOG_LEVEL_DEBUG "Role $role has been granted."
        fi
    done
fi

# サービスアカウントキーの生成と保存
KEY_FILE="sa-key.json"
log $LOG_LEVEL_INFO "Generating service account key and saving to ${KEY_FILE}"
gcloud iam service-accounts keys create "${KEY_FILE}" \
    --iam-account="$SERVICE_ACCOUNT_EMAIL" \
    --project="$PROJECT_ID"
log $LOG_LEVEL_INFO "Service account key has been saved to ${KEY_FILE}"

# 環境変数ファイルの作成または更新
ENV_FILE="$HOME/.obp_env"
log $LOG_LEVEL_INFO "Saving environment variables to $ENV_FILE"
cat << EOF > $ENV_FILE
export OBP_PROJECT_ID=$PROJECT_ID
export OBP_REGION=$REGION
export OBP_SERVICE_ACCOUNT_EMAIL=$SERVICE_ACCOUNT_EMAIL
export GOOGLE_APPLICATION_CREDENTIALS=${KEY_FILE}
EOF

log $LOG_LEVEL_INFO "Environment variables have been saved to $ENV_FILE"
log $LOG_LEVEL_INFO "Please run the following command to load the environment variables:"
log $LOG_LEVEL_INFO "source $ENV_FILE"
log $LOG_LEVEL_INFO "Service account setup completed successfully."
