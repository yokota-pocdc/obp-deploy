#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -e

# プロジェクトIDの設定
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo "プロジェクトIDが設定されていません。"
    exit 1
fi

echo "現在のプロジェクト: $PROJECT_ID"

# Secret Manager APIの有効化
echo "Secret Manager APIを有効化しています..."
gcloud services enable secretmanager.googleapis.com

# APIが有効化されたことを確認
echo "Secret Manager APIが有効化されていることを確認しています..."
API_ENABLED=$(gcloud services list --enabled --format="value(NAME)" | grep secretmanager.googleapis.com || true)
if [ -z "$API_ENABLED" ]; then
    echo "Secret Manager APIの有効化に失敗しました。"
    exit 1
fi

echo "Secret Manager APIが正常に有効化されました。"

# シークレット名とJSONファイル名の設定
SECRET_NAME="add3-credential"
JSON_FILE="add3_credential.json"

# JSONファイルの存在確認
if [ ! -f "$JSON_FILE" ]; then
    echo "エラー: $JSON_FILE が見つかりません。"
    exit 1
fi

# シークレットの存在確認
if gcloud secrets describe $SECRET_NAME &>/dev/null; then
    echo "シークレット '$SECRET_NAME' は既に存在します。新しいバージョンを追加します。"
    # 新しいバージョンを追加
    gcloud secrets versions add $SECRET_NAME --data-file="$JSON_FILE"
    echo "シークレット '$SECRET_NAME' に新しいバージョンが追加されました。"
else
    echo "シークレット '$SECRET_NAME' を新規作成しています..."
    # シークレットの作成と初期値の設定
    gcloud secrets create $SECRET_NAME --replication-policy="automatic" --data-file="$JSON_FILE"
    echo "シークレット '$SECRET_NAME' が作成され、初期値が設定されました。"
fi

echo "セットアップが完了しました。"
