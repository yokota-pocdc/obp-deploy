#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -e

echo "Create or update service account for OBP and set environment variables"

# 変数設定
PROJECT_ID=$(gcloud config get-value project)
echo "Your project id is: ${PROJECT_ID}"

SERVICE_ACCOUNT_NAME="obp-deployment-sa"
SERVICE_ACCOUNT_DISPLAY_NAME="OBP Deployment Service Account"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# サービスアカウントの存在確認
if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
    echo "サービスアカウント $SERVICE_ACCOUNT_EMAIL は既に存在します。"
else
    echo "サービスアカウント $SERVICE_ACCOUNT_EMAIL を作成します。"
    # サービスアカウントの作成
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="$SERVICE_ACCOUNT_DISPLAY_NAME" \
        --project=$PROJECT_ID

    echo "サービスアカウント $SERVICE_ACCOUNT_EMAIL が作成されました。"
fi

# 必要な役割を付与
echo "サービスアカウントに必要な役割を付与します。"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/storage.objectViewer"

echo "役割の付与が完了しました。"

# サービスアカウントキーの生成
KEY_FILE="${SERVICE_ACCOUNT_NAME}-key.json"
echo "サービスアカウントキーを生成します: $KEY_FILE"

gcloud iam service-accounts keys create $KEY_FILE \
    --iam-account=$SERVICE_ACCOUNT_EMAIL

echo "サービスアカウントキーが生成されました: $KEY_FILE"

# 環境変数をファイルに書き込む
ENV_FILE="$HOME/.obp_env"
cat > "$ENV_FILE" << EOF
# Service Account Information
export OBP_SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME}"
export OBP_SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_EMAIL}"
export OBP_PROJECT_ID="${PROJECT_ID}"
export OBP_SERVICE_ACCOUNT_KEY_FILE="$(pwd)/${KEY_FILE}"
EOF

echo "環境変数が $ENV_FILE に書き込まれました。"
echo "これらの環境変数を使用するには、次のコマンドを実行してください："
echo "source $ENV_FILE"

echo "注意: 生成されたキーファイル ($KEY_FILE) は安全に保管してください。不要になった場合は適切に削除してください。"
