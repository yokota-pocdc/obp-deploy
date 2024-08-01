#!/bin/bash

# 変数設定
VPC_NAME="obp-vpc-network"
SUBNET_NAME="obp-subnet"
REGION="asia-northeast1"
SUBNET_RANGE="10.0.0.0/24"
SSH_FIREWALL_RULE_NAME="allow-ssh-from-external"

# VPCネットワークの存在確認
if ! gcloud compute networks describe $VPC_NAME &> /dev/null; then
    echo "Creating VPC network: $VPC_NAME"
    gcloud compute networks create $VPC_NAME --subnet-mode=custom
else
    echo "VPC network $VPC_NAME already exists."
fi

# サブネットの存在確認
if ! gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION &> /dev/null; then
    echo "Creating subnet: $SUBNET_NAME"
    gcloud compute networks subnets create $SUBNET_NAME \
        --network=$VPC_NAME \
        --region=$REGION \
        --range=$SUBNET_RANGE
else
    echo "Subnet $SUBNET_NAME already exists in region $REGION."
fi

# 内部通信用ファイアウォールルールの存在確認
if ! gcloud compute firewall-rules describe allow-internal &> /dev/null; then
    echo "Creating firewall rule: allow-internal"
    gcloud compute firewall-rules create allow-internal \
        --network=$VPC_NAME \
        --allow=tcp,udp,icmp \
        --source-ranges=$SUBNET_RANGE
else
    echo "Firewall rule allow-internal already exists."
fi

# SSH用ファイアウォールルールの存在確認
if ! gcloud compute firewall-rules describe $SSH_FIREWALL_RULE_NAME &> /dev/null; then
    echo "Creating firewall rule: $SSH_FIREWALL_RULE_NAME"
    gcloud compute firewall-rules create $SSH_FIREWALL_RULE_NAME \
        --network=$VPC_NAME \
        --allow=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --description="Allow SSH from any source"
else
    echo "Firewall rule $SSH_FIREWALL_RULE_NAME already exists."
fi

echo "VPC, subnet, and firewall rules setup completed."

