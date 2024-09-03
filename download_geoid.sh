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

# リージョンをコマンドライン引数から取得、デフォルトはasia-northeast1
REGION=${1:-"asia-northeast1"}

# 送信元と送信先のバケット名を設定
SOURCE_BUCKET="gs://obp-geoid"
DEST_BUCKET="gs://${OBP_PROJECT_ID}-geoid"

echo "Using region: $REGION"

# 送信先バケットが存在するか確認し、存在しない場合は作成
if ! gsutil ls $DEST_BUCKET &>/dev/null; then
    echo "送信先バケット ${DEST_BUCKET} が存在しません。${REGION}リージョンで作成します..."
    gsutil mb -p $OBP_PROJECT_ID -l $REGION $DEST_BUCKET
else
    echo "送信先バケット ${DEST_BUCKET} は既に存在します。"
    # 既存バケットのリージョンを確認（小文字に変換して比較）
    BUCKET_REGION=$(gsutil ls -L -b $DEST_BUCKET | grep "Location constraint:" | awk '{print tolower($3)}')
    if [ "${BUCKET_REGION,,}" != "${REGION,,}" ]; then
        echo "警告: 既存のバケットは ${BUCKET_REGION} リージョンにあります。指定された ${REGION} とは異なります。"
    else
        echo "バケットは指定されたリージョン ${REGION} に存在します。"
    fi
fi

# すべてのTIFFファイルをコピー
echo "すべてのTIFFファイルをコピーしています..."
gsutil -m rsync -r $SOURCE_BUCKET $DEST_BUCKET

# TIFFファイル以外を削除
echo "TIFFファイル以外を削除しています..."
gsutil -m rm $(gsutil ls ${DEST_BUCKET}/'*' | grep -vE "\.tif$|\.tiff$") || true

echo "コピーが完了しました。"

# コピーされたファイル数とサイズを表示
echo "コピーされたファイルの統計:"
COPIED_FILES=$(gsutil ls -l $DEST_BUCKET | grep -E "\.tif$|\.tiff$" | wc -l)
echo "コピーされたファイル数: $COPIED_FILES"
gsutil du -sh $DEST_BUCKET
