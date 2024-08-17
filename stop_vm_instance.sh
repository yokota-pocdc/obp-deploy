#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -euo pipefail

# ユーティリティスクリプトの読み込み
source ./utils.sh

# デフォルト値の設定
DEFAULT_REGION="asia-northeast1"
PROJECT_ID=$(gcloud config get-value project)
INSTANCE_NAME="obp-master-vm"

# 変数の初期化
REGION=$DEFAULT_REGION

# 引数の処理
while [[ $# -gt 0 ]]; do
  case $1 in
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    --project-id=*)
      PROJECT_ID="${1#*=}"
      shift
      ;;
    *)
      handle_error 1 "Unknown argument: $1"
      ;;
  esac
done

log $LOG_LEVEL_INFO "Region: $REGION"
log $LOG_LEVEL_INFO "Project ID: $PROJECT_ID"

# インスタンスの存在確認
if ! check_resource_exists "compute instances" "$INSTANCE_NAME" "$PROJECT_ID" "--filter=name=$INSTANCE_NAME"; then
  handle_error 1 "Instance $INSTANCE_NAME does not exist."
fi

# インスタンスのゾーンを取得
ZONE=$(gcloud compute instances list --filter="name=$INSTANCE_NAME" --project=$PROJECT_ID --format="value(zone)")
if [ -z "$ZONE" ]; then
  handle_error 1 "Failed to get zone for instance $INSTANCE_NAME."
fi

log $LOG_LEVEL_INFO "Instance $INSTANCE_NAME zone: $ZONE"

# インスタンスの状態を確認
INSTANCE_STATUS=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID --format="value(status)")

if [ "$INSTANCE_STATUS" = "RUNNING" ]; then
  log $LOG_LEVEL_INFO "Stopping instance $INSTANCE_NAME."
  if gcloud compute instances stop $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID; then
    log $LOG_LEVEL_INFO "Instance $INSTANCE_NAME stopped successfully."
  else
    handle_error 1 "Failed to stop instance $INSTANCE_NAME."
  fi
elif [ "$INSTANCE_STATUS" = "TERMINATED" ]; then
  log $LOG_LEVEL_INFO "Instance $INSTANCE_NAME is already stopped."
else
  handle_error 1 "Instance $INSTANCE_NAME is in an unexpected state: $INSTANCE_STATUS"
fi

log $LOG_LEVEL_INFO "Operation on instance $INSTANCE_NAME completed."
