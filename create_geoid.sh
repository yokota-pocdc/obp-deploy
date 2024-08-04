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
PROJECT_ID=$OBP_PROJECT_ID
DATASET_ID="geoid"
TABLE_ID="gsigeo2024"
GCS_BUCKET="obp-geoid"
GCS_PATH="*.avro"

# データセットの存在確認と作成
if ! bq show --dataset "${PROJECT_ID}:${DATASET_ID}" &>/dev/null; then
    echo "Creating dataset ${DATASET_ID}"
    bq mk --dataset "${PROJECT_ID}:${DATASET_ID}"
else
    echo "Dataset ${DATASET_ID} already exists"
fi

# テーブルの存在確認
if bq show "${PROJECT_ID}:${DATASET_ID}.${TABLE_ID}" &>/dev/null; then
    # テーブルが存在する場合、行数を確認
    ROW_COUNT=$(bq query --nouse_legacy_sql --format=csv \
        "SELECT row_count FROM \`${PROJECT_ID}.${DATASET_ID}.__TABLES__\`
         WHERE table_id = '${TABLE_ID}'" \
        | tail -n 1)

    if [ -n "$ROW_COUNT" ] && [ "$ROW_COUNT" -gt "0" ]; then
        echo "Table ${TABLE_ID} already contains data (${ROW_COUNT} rows). Skipping data import."
        exit 0
    fi
fi

echo "Creating or updating BigQuery table ${TABLE_ID} from Avro files in GCS"
bq load \
    --source_format=AVRO \
    --autodetect \
    --replace \
    "${DATASET_ID}.${TABLE_ID}" \
    "gs://${GCS_BUCKET}/${GCS_PATH}"

# テーブル作成の確認
if bq show "${DATASET_ID}.${TABLE_ID}" &>/dev/null; then
    echo "Table ${TABLE_ID} created or updated successfully in dataset ${DATASET_ID}"
    # テーブル情報の表示
    bq show --format=prettyjson "${DATASET_ID}.${TABLE_ID}"
else
    echo "Failed to create or update table ${TABLE_ID}"
    exit 1
fi

echo "Processing completed."
