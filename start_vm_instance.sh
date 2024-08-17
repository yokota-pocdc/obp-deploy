#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -euo pipefail

# ユーティリティスクリプトの読み込み
source ./utils.sh

# 環境変数ファイルを読み込む
ENV_FILE="$HOME/.obp_env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    handle_error 1 "Environment variable file $ENV_FILE not found. Please run create_sa.sh first."
fi

# デフォルト値の設定
PROJECT_ID=""
VPC_NAME=""
SUBNET_NAME=""
REGION=""
MACHINE_TYPE="e2-medium"
INSTANCE_NAME="obp-master-vm"
SERVICE_ACCOUNT_EMAIL=""
SA_KEY_FILE="sa-key.json"

# 引数の処理
while [[ $# -gt 0 ]]; do
  case $1 in
    --project-id=*)
      PROJECT_ID="${1#*=}"
      shift
      ;;
    --vpc-name=*)
      VPC_NAME="${1#*=}"
      shift
      ;;
    --subnet-name=*)
      SUBNET_NAME="${1#*=}"
      shift
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    --machine-type=*)
      MACHINE_TYPE="${1#*=}"
      shift
      ;;
    --service-account-email=*)
      SERVICE_ACCOUNT_EMAIL="${1#*=}"
      shift
      ;;
    --sa-key-file=*)
      SA_KEY_FILE="${1#*=}"
      shift
      ;;
    *)
      handle_error 1 "Unknown argument: $1"
      ;;
  esac
done

# 必須パラメータの確認
validate_env_vars "PROJECT_ID" "VPC_NAME" "SUBNET_NAME" "REGION" "SERVICE_ACCOUNT_EMAIL"

log $LOG_LEVEL_INFO "Project ID: $PROJECT_ID"
log $LOG_LEVEL_INFO "VPC Name: $VPC_NAME"
log $LOG_LEVEL_INFO "Subnet Name: $SUBNET_NAME"
log $LOG_LEVEL_INFO "Region: $REGION"
log $LOG_LEVEL_INFO "Machine Type: $MACHINE_TYPE"
log $LOG_LEVEL_INFO "Service Account Email: $SERVICE_ACCOUNT_EMAIL"

# インスタンスの存在確認
if check_resource_exists "compute instances" "$INSTANCE_NAME" "$PROJECT_ID" "--zone=${REGION}-b"; then
    log $LOG_LEVEL_INFO "Instance $INSTANCE_NAME found."
    
    # インスタンスの状態を確認
    INSTANCE_STATUS=$(gcloud compute instances describe $INSTANCE_NAME --project=$PROJECT_ID --zone=${REGION}-b --format="value(status)")
    
    if [ "$INSTANCE_STATUS" = "RUNNING" ]; then
        log $LOG_LEVEL_INFO "Instance $INSTANCE_NAME is already running."
    elif [ "$INSTANCE_STATUS" = "TERMINATED" ]; then
        log $LOG_LEVEL_INFO "Starting instance $INSTANCE_NAME."
        gcloud compute instances start $INSTANCE_NAME --project=$PROJECT_ID --zone=${REGION}-b
        log $LOG_LEVEL_INFO "Instance $INSTANCE_NAME has been started."
    else
        log $LOG_LEVEL_WARN "Instance $INSTANCE_NAME is in state: $INSTANCE_STATUS"
        log $LOG_LEVEL_WARN "Please check the instance state and handle manually if necessary."
    fi
else
    log $LOG_LEVEL_INFO "Instance $INSTANCE_NAME not found. Creating a new instance."
    
    # create_vm_instance.sh スクリプトを呼び出す
    ./create_vm_instance.sh \
        --project-id=$PROJECT_ID \
        --vpc-name=$VPC_NAME \
        --subnet-name=$SUBNET_NAME \
        --region=$REGION \
        --machine-type=$MACHINE_TYPE \
        --service-account-email=$SERVICE_ACCOUNT_EMAIL \
        --sa-key-file=$SA_KEY_FILE
fi

log $LOG_LEVEL_INFO "Operation completed."
