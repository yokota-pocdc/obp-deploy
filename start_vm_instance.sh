#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -e

# 環境変数ファイルを読み込む
ENV_FILE="$HOME/.obp_env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "エラー: 環境変数ファイル $ENV_FILE が見つかりません。create_sa.sh を実行してください。"
    exit 1
fi

# デフォルト値の設定
DEFAULT_REGION="asia-northeast1"
DEFAULT_MACHINE_TYPE="e2-medium"
SA_KEY_FILE="obp-deployment-sa-key.json"

# 変数の初期化
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
    --sa-key-file=*)
      SA_KEY_FILE="${1#*=}"
      shift
      ;;
    *)
      echo "エラー: 不明な引数 $1"
      echo "使用方法: $0 [--region=REGION] [--machine-type=MACHINE_TYPE] [--sa-key-file=FILE]"
      exit 1
      ;;
  esac
done

# VMインスタンス名を設定
INSTANCE_NAME="obp-master-vm"

# サービスアカウントキーファイルの存在確認
if [ ! -f "$SA_KEY_FILE" ]; then
    echo "エラー: サービスアカウントキーファイル $SA_KEY_FILE が見つかりません。"
    exit 1
fi

# インスタンスの存在確認
INSTANCE_EXISTS=$(gcloud compute instances list --filter="name=$INSTANCE_NAME" --format="value(name)")

if [ -z "$INSTANCE_EXISTS" ]; then
  echo "インスタンス $INSTANCE_NAME が存在しません。新規作成します。"
  /bin/bash create_vm_instance.sh --region="$REGION" --machine-type="$MACHINE_TYPE" --sa-key-file="$SA_KEY_FILE"
else
  # インスタンスの状態を確認
  INSTANCE_STATUS=$(gcloud compute instances describe $INSTANCE_NAME --zone=${REGION}-b --format="value(status)")
  
  if [ "$INSTANCE_STATUS" = "TERMINATED" ]; then
    echo "インスタンス $INSTANCE_NAME は停止しています。起動します。"
    gcloud compute instances start $INSTANCE_NAME --zone=${REGION}-b
  elif [ "$INSTANCE_STATUS" = "RUNNING" ]; then
    echo "インスタンス $INSTANCE_NAME は既に起動しています。"
  else
    echo "インスタンス $INSTANCE_NAME の状態: $INSTANCE_STATUS"
    exit 1
  fi

  # インスタンスが完全に起動し、SSHが利用可能になるまで待機
  echo "インスタンスの起動とSSHの準備を待っています..."
  while ! gcloud compute ssh $INSTANCE_NAME --zone=${REGION}-b --command="echo SSH is ready" &>/dev/null; do
    echo "SSHの準備中..."
    sleep 10
  done
  echo "SSHが利用可能になりました。"

  # サービスアカウントキーファイルの転送
  echo "サービスアカウントキーファイルを転送しています..."
  gcloud compute scp $SA_KEY_FILE $INSTANCE_NAME:~/obp-deployment-sa-key.json --zone=${REGION}-b

  # キーファイルの権限を設定
  gcloud compute ssh $INSTANCE_NAME --zone=${REGION}-b --command="chmod 600 ~/obp-deployment-sa-key.json"

  echo "サービスアカウントキーファイルが転送され、権限が設定されました。"
fi

echo "インスタンス $INSTANCE_NAME の操作が完了しました。"
