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

echo "Create network for OBP"

# 変数設定
VPC_NAME="obp-vpc-network"
SUBNET_NAME="obp-subnet"
REGION=${1:-"asia-northeast1"}
SUBNET_RANGE="10.0.0.0/24"
SSH_FIREWALL_RULE_NAME="allow-ssh-from-external"

echo "Using region: ${REGION}"

# VPCネットワークの存在確認
if ! gcloud compute networks describe $VPC_NAME --project=$OBP_PROJECT_ID &> /dev/null; then
    echo "Creating VPC network: $VPC_NAME"
    gcloud compute networks create $VPC_NAME --project=$OBP_PROJECT_ID --subnet-mode=custom
else
    echo "VPC network $VPC_NAME already exists."
fi

# サブネットの存在確認
if ! gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION --project=$OBP_PROJECT_ID &> /dev/null; then
    echo "Creating subnet: $SUBNET_NAME"
    gcloud compute networks subnets create $SUBNET_NAME \
        --project=$OBP_PROJECT_ID \
        --network=$VPC_NAME \
        --region=$REGION \
        --range=$SUBNET_RANGE
else
    echo "Subnet $SUBNET_NAME already exists in region $REGION."
fi

# 内部通信用ファイアウォールルールの存在確認
if ! gcloud compute firewall-rules describe allow-internal --project=$OBP_PROJECT_ID &> /dev/null; then
    echo "Creating firewall rule: allow-internal"
    gcloud compute firewall-rules create allow-internal \
        --project=$OBP_PROJECT_ID \
        --network=$VPC_NAME \
        --allow=tcp,udp,icmp \
        --source-ranges=$SUBNET_RANGE
else
    echo "Firewall rule allow-internal already exists."
fi

# SSH用ファイアウォールルールの存在確認
if ! gcloud compute firewall-rules describe $SSH_FIREWALL_RULE_NAME --project=$OBP_PROJECT_ID &> /dev/null; then
    echo "Creating firewall rule: $SSH_FIREWALL_RULE_NAME"
    gcloud compute firewall-rules create $SSH_FIREWALL_RULE_NAME \
        --project=$OBP_PROJECT_ID \
        --network=$VPC_NAME \
        --allow=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --description="Allow SSH from any source"
else
    echo "Firewall rule $SSH_FIREWALL_RULE_NAME already exists."
fi

# 環境変数ファイルにVPC名とサブネット名を追加
echo "export OBP_VPC_NAME=\"${VPC_NAME}\"" >> $ENV_FILE
echo "export OBP_SUBNET_NAME=\"${SUBNET_NAME}\"" >> $ENV_FILE

echo "VPC, subnet, and firewall rules setup completed."
