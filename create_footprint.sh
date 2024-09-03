#!/bin/bash

# 環境変数の設定
PROJECT_ID=$OBP_PROJECT_ID
DATASET_ID="building"
TABLE_ID="foorprint"
GCS_BUCKET="obp-building"
GCS_PATH="footprint_*.avro"

# データセットの存在確認と作成
if ! bq show --dataset "${PROJECT_ID}:${DATASET_ID}" &>/dev/null; then
    echo "Creating dataset ${DATASET_ID}"
    bq mk --dataset "${PROJECT_ID}:${DATASET_ID}"
else
    echo "Dataset ${DATASET_ID} already exists"
fi

# BigQueryテーブルの作成（Avroスキーマを自動検出）
echo "Creating BigQuery table ${TABLE_ID} from Avro files in GCS"
bq load \
    --source_format=AVRO \
    --autodetect \
    --replace \
    "${DATASET_ID}.${TABLE_ID}" \
    "gs://${GCS_BUCKET}/${GCS_PATH}"

# テーブル作成の確認
if bq show "${DATASET_ID}.${TABLE_ID}" &>/dev/null; then
    echo "Table ${TABLE_ID} created successfully in dataset ${DATASET_ID}"
    # テーブル情報の表示
    bq show --format=prettyjson "${DATASET_ID}.${TABLE_ID}"
else
    echo "Failed to create table ${TABLE_ID}"
fi
