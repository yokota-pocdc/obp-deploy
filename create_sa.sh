#!/bin/bash

echo "Create service account for OBP and set environment variables"

# 変数設定
PROJECT_ID=`gcloud config get-value project`
echo "Your project id is:${PROJECT_ID}"

SERVICE_ACCOUNT_NAME="obp-deployment-sa"
SERVICE_ACCOUNT_DISPLAY_NAME="OBP Deployment Service Account"

# サービスアカウントの作成
gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
    --display-name="$SERVICE_ACCOUNT_DISPLAY_NAME" \
    --project=$PROJECT_ID

# サービスアカウントのメールアドレスを取得
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 必要な役割を付与
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/dataflow.worker"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/storage.admin"

# BigQuery関連の権限を追加
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/bigquery.jobUser"

# サービスアカウントキーの作成 (オプション)
#gcloud iam service-accounts keys create key.json \
#    --iam-account=$SERVICE_ACCOUNT_EMAIL

echo "Service account $SERVICE_ACCOUNT_EMAIL has been created and granted necessary permissions, including BigQuery access."

# 環境変数をエクスポートする行を作成
EXPORT_LINES="
# Service Account Information
export OBP_SERVICE_ACCOUNT_NAME=\"${SERVICE_ACCOUNT_NAME}\"
export OBP_SERVICE_ACCOUNT_EMAIL=\"${SERVICE_ACCOUNT_EMAIL}\"
export OBP_PROJECT_ID=\"${PROJECT_ID}\"
"

# ~/.bashrcファイルに環境変数を追加
echo "$EXPORT_LINES" >> ~/.bashrc

# 現在のシェルセッションに環境変数を適用
eval "$EXPORT_LINES"

echo "Service account information has been added to ~/.bashrc and set as environment variables."
echo "Please run 'source ~/.bashrc' or start a new terminal session to apply changes."