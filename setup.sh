#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -e

# デフォルト値の設定
DEFAULT_REGION="asia-northeast1"
DEFAULT_MACHINE_TYPE="e2-medium"

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
      echo "エラー: 不明な引数 $1"
      echo "使用方法: $0 [--region=REGION] [--machine-type=MACHINE_TYPE]"
      exit 1
      ;;
  esac
done

echo "使用するリージョン: $REGION"
echo "使用するマシンタイプ: $MACHINE_TYPE"

# create_sa.shの実行
#/bin/bash create_sa.sh "$REGION"

# create_nw.shの実行
/bin/bash create_nw.sh "$REGION"

# credential.shの実行
/bin/bash credential.sh "$REGION"

/bin/bash create_geoid.sh

# download_dem.shの実行（リージョンパラメータを渡す）
# /bin/bash download_dem.sh "$REGION"

# start_vm_instance.shの実行（リージョンとマシンタイプパラメータを名前付き引数として渡す）
/bin/bash start_vm_instance.sh --region="$REGION" --machine-type="$MACHINE_TYPE"

echo "セットアップが完了しました。リージョン: $REGION、マシンタイプ: $MACHINE_TYPE"
