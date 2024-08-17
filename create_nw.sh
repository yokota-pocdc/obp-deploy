#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -euo pipefail

# ユーティリティスクリプトの読み込み
source ./utils.sh

# デフォルト値の設定
PROJECT_ID=""
VPC_NAME=""
SUBNET_NAME=""
REGION=""
SUBNET_RANGE="10.0.0.0/24"

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
    *)
      handle_error 1 "Unknown argument: $1"
      ;;
  esac
done

# 必須パラメータの確認
validate_env_vars "PROJECT_ID" "VPC_NAME" "SUBNET_NAME" "REGION"

log $LOG_LEVEL_INFO "Project ID: $PROJECT_ID"
log $LOG_LEVEL_INFO "VPC Name: $VPC_NAME"
log $LOG_LEVEL_INFO "Subnet Name: $SUBNET_NAME"
log $LOG_LEVEL_INFO "Region: $REGION"

# VPCネットワークの存在確認と作成
if ! check_resource_exists "compute networks" "$VPC_NAME" "$PROJECT_ID"; then
    log $LOG_LEVEL_INFO "Creating VPC network: $VPC_NAME"
    gcloud compute networks create $VPC_NAME --project=$PROJECT_ID --subnet-mode=custom
    
    # VPCネットワークの作成完了を待つ
    wait_for_operation "compute networks" "$VPC_NAME" 300 10
    
    # 追加の待機時間（5秒）
    log $LOG_LEVEL_INFO "Waiting additional 5 seconds for VPC network to stabilize..."
    sleep 5
else
    log $LOG_LEVEL_INFO "VPC network $VPC_NAME already exists."
fi

# サブネットの存在確認と作成/更新
create_subnet() {
    if ! check_resource_exists "compute networks subnets" "$SUBNET_NAME" "$PROJECT_ID" "--region=$REGION"; then
        log $LOG_LEVEL_INFO "Creating subnet: $SUBNET_NAME in VPC $VPC_NAME with Private Google Access enabled"
        gcloud compute networks subnets create $SUBNET_NAME \
            --project=$PROJECT_ID \
            --network=$VPC_NAME \
            --region=$REGION \
            --range=$SUBNET_RANGE \
            --enable-private-ip-google-access
    else
        log $LOG_LEVEL_INFO "Subnet $SUBNET_NAME already exists in VPC $VPC_NAME and region $REGION. Updating to enable Private Google Access."
        gcloud compute networks subnets update $SUBNET_NAME \
            --project=$PROJECT_ID \
            --region=$REGION \
            --enable-private-ip-google-access
    fi
}

# サブネット作成を最大3回試行
max_retries=3
retry_count=0
while [ $retry_count -lt $max_retries ]; do
    if create_subnet; then
        log $LOG_LEVEL_INFO "Subnet created/updated successfully."
        break
    else
        retry_count=$((retry_count+1))
        if [ $retry_count -lt $max_retries ]; then
            log $LOG_LEVEL_WARN "Subnet creation/update failed. Retrying in 30 seconds... (Attempt $retry_count of $max_retries)"
            sleep 30
        else
            handle_error 1 "Failed to create/update subnet after $max_retries attempts."
        fi
    fi
done

# サブネットの存在を確認
if ! check_resource_exists "compute networks subnets" "$SUBNET_NAME" "$PROJECT_ID" "--region=$REGION"; then
    handle_error 1 "Subnet $SUBNET_NAME was not created successfully."
fi

# Firewall ルール作成関数
create_firewall_rule() {
    local rule_name=$1
    local network=$2
    local allow=$3
    local source_ranges=$4

    log $LOG_LEVEL_INFO "Creating firewall rule: $rule_name"
    local output
    if ! output=$(gcloud compute firewall-rules create $rule_name \
        --project=$PROJECT_ID \
        --network=$network \
        --allow=$allow \
        --source-ranges=$source_ranges 2>&1); then
        log $LOG_LEVEL_ERROR "Failed to create firewall rule: $rule_name"
        log $LOG_LEVEL_ERROR "Error details: $output"
        return 1
    fi
    log $LOG_LEVEL_INFO "Firewall rule $rule_name created successfully."
    return 0
}

# 内部通信用ファイアウォールルールの作成
INTERNAL_FIREWALL_RULE_NAME="allow-internal-${VPC_NAME}"
if ! check_resource_exists "compute firewall-rules" "$INTERNAL_FIREWALL_RULE_NAME" "$PROJECT_ID"; then
    log $LOG_LEVEL_INFO "Creating internal firewall rule: $INTERNAL_FIREWALL_RULE_NAME"
    max_retries=3
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if create_firewall_rule "$INTERNAL_FIREWALL_RULE_NAME" "$VPC_NAME" "tcp,udp,icmp" "$SUBNET_RANGE"; then
            break
        else
            retry_count=$((retry_count+1))
            if [ $retry_count -lt $max_retries ]; then
                log $LOG_LEVEL_WARN "Retrying internal firewall rule creation in 30 seconds... (Attempt $retry_count of $max_retries)"
                sleep 30
            else
                handle_error 1 "Failed to create internal firewall rule after $max_retries attempts."
            fi
        fi
    done
else
    log $LOG_LEVEL_INFO "Internal firewall rule $INTERNAL_FIREWALL_RULE_NAME already exists."
fi

# SSH用ファイアウォールルールの作成
SSH_FIREWALL_RULE_NAME="allow-ssh-${VPC_NAME}"
if ! check_resource_exists "compute firewall-rules" "$SSH_FIREWALL_RULE_NAME" "$PROJECT_ID"; then
    log $LOG_LEVEL_INFO "Creating SSH firewall rule: $SSH_FIREWALL_RULE_NAME"
    max_retries=3
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if create_firewall_rule "$SSH_FIREWALL_RULE_NAME" "$VPC_NAME" "tcp:22" "0.0.0.0/0"; then
            break
        else
            retry_count=$((retry_count+1))
            if [ $retry_count -lt $max_retries ]; then
                log $LOG_LEVEL_WARN "Retrying SSH firewall rule creation in 30 seconds... (Attempt $retry_count of $max_retries)"
                sleep 30
            else
                handle_error 1 "Failed to create SSH firewall rule after $max_retries attempts."
            fi
        fi
    done
else
    log $LOG_LEVEL_INFO "SSH firewall rule $SSH_FIREWALL_RULE_NAME already exists."
fi

log $LOG_LEVEL_INFO "VPC network, subnet, and firewall rules setup completed successfully."
