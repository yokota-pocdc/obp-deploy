#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -euo pipefail

# ユーティリティスクリプトの読み込み
source ./utils.sh

# デフォルト値の設定
DEFAULT_REGION="us-central1"
DEFAULT_MACHINE_TYPE="e2-medium"
PROJECT_ID=$(gcloud config get-value project)
VPC_NAME="obp-vpc-${PROJECT_ID}"
SUBNET_NAME="obp-subnet"
SERVICE_ACCOUNT_NAME="obp-deployment-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 引数の解析
REGION=$DEFAULT_REGION
MACHINE_TYPE=$DEFAULT_MACHINE_TYPE

# 引数の処理
while [[ $# -gt 0 ]]; do
  case $1 in
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    --machine-type=*)
      MACHINE_TYPE="${1#*=}"
      shift
      ;;
    *)
      handle_error 1 "Unknown argument: $1"
      ;;
  esac
done

# 環境変数の検証
validate_env_vars "PROJECT_ID" "VPC_NAME" "SUBNET_NAME" "SERVICE_ACCOUNT_NAME" "SERVICE_ACCOUNT_EMAIL"

log $LOG_LEVEL_INFO "Starting setup for project: $PROJECT_ID"
log $LOG_LEVEL_INFO "VPC name: $VPC_NAME"
log $LOG_LEVEL_INFO "Subnet name: $SUBNET_NAME"
log $LOG_LEVEL_INFO "Region: $REGION"
log $LOG_LEVEL_INFO "Machine type: $MACHINE_TYPE"
log $LOG_LEVEL_INFO "Service account name: $SERVICE_ACCOUNT_NAME"
log $LOG_LEVEL_INFO "Service account email: $SERVICE_ACCOUNT_EMAIL"

# 必要なAPIを有効化
apis=(
  "compute.googleapis.com"
  "iam.googleapis.com"
  "cloudresourcemanager.googleapis.com"
  "artifactregistry.googleapis.com"
  "bigquery.googleapis.com"
  "bigquerydatatransfer.googleapis.com"
  "serviceusage.googleapis.com"
)

for api in "${apis[@]}"; do
  enable_api $api $PROJECT_ID
done

# サブスクリプトの実行
log $LOG_LEVEL_INFO "Creating service account"
./create_sa.sh --project-id="$PROJECT_ID" --region="$REGION" --service-account-name="$SERVICE_ACCOUNT_NAME"

log $LOG_LEVEL_INFO "Creating network"
./create_nw.sh --project-id="$PROJECT_ID" --vpc-name="$VPC_NAME" --subnet-name="$SUBNET_NAME" --region="$REGION"

log $LOG_LEVEL_INFO "Setting up credentials"
./credential.sh --project-id="$PROJECT_ID" --region="$REGION"

log $LOG_LEVEL_INFO "Starting VM instance"
./start_vm_instance.sh --project-id="$PROJECT_ID" --vpc-name="$VPC_NAME" --subnet-name="$SUBNET_NAME" --region="$REGION" --machine-type="$MACHINE_TYPE" --service-account-email="$SERVICE_ACCOUNT_EMAIL"

log $LOG_LEVEL_INFO "Setup completed successfully"
log $LOG_LEVEL_INFO "Project: $PROJECT_ID, VPC: $VPC_NAME, Subnet: $SUBNET_NAME, Region: $REGION, Machine type: $MACHINE_TYPE, Service account: $SERVICE_ACCOUNT_EMAIL"

