#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -e

# デフォルト値の設定
DEFAULT_REGION="asia-northeast1"

# 変数の初期化
REGION=$DEFAULT_REGION

# 引数の処理
while [[ $# -gt 0 ]]; do
  case $1 in
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    *)
      echo "エラー: 不明な引数 $1"
      echo "使用方法: $0 [--region=REGION]"
      exit 1
      ;;
  esac
done

# VMインスタンス名を設定
INSTANCE_NAME="obp-master-vm"

# インスタンスの存在確認
INSTANCE_EXISTS=$(gcloud compute instances list --filter="name=$INSTANCE_NAME" --format="value(name)")

if [ -z "$INSTANCE_EXISTS" ]; then
  echo "インスタンス $INSTANCE_NAME が存在しません。"
else
  # インスタンスの状態を確認
  INSTANCE_STATUS=$(gcloud compute instances describe $INSTANCE_NAME --zone=${REGION}-b --format="value(status)")
  
  if [ "$INSTANCE_STATUS" = "RUNNING" ]; then
    echo "インスタンス $INSTANCE_NAME を停止します。"
    gcloud compute instances stop $INSTANCE_NAME --zone=${REGION}-b
  elif [ "$INSTANCE_STATUS" = "TERMINATED" ]; then
    echo "インスタンス $INSTANCE_NAME は既に停止しています。"
  else
    echo "インスタンス $INSTANCE_NAME の状態: $INSTANCE_STATUS"
  fi
fi

echo "インスタンス $INSTANCE_NAME の操作が完了しました。"
