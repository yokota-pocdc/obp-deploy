#!/bin/bash

# エラーが発生した場合にスクリプトを終了
set -euo pipefail

# ユーティリティスクリプトの読み込み
source ./utils.sh

# 環境変数ファイルを読み込む
ENV_FILE="$HOME/.obp_env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    handle_error 1 "Environment variable file $ENV_FILE not found. Please run create_sa.sh first."
fi

# デフォルト値の設定
PROJECT_ID=""
VPC_NAME=""
SUBNET_NAME=""
REGION=""
MACHINE_TYPE="e2-medium"
INSTANCE_NAME="obp-master-vm"
SERVICE_ACCOUNT_EMAIL=""
BOOT_DISK_SIZE="10GB"
DATA_DISK_SIZE="200GB"
SA_KEY_FILE="sa-key.json"

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
    --machine-type=*)
      MACHINE_TYPE="${1#*=}"
      shift
      ;;
    --service-account-email=*)
      SERVICE_ACCOUNT_EMAIL="${1#*=}"
      shift
      ;;
    --sa-key-file=*)
      SA_KEY_FILE="${1#*=}"
      shift
      ;;
    *)
      handle_error 1 "Unknown argument: $1"
      ;;
  esac
done

# 必須パラメータの確認
validate_env_vars "PROJECT_ID" "VPC_NAME" "SUBNET_NAME" "REGION" "SERVICE_ACCOUNT_EMAIL"

# サービスアカウントキーファイルの存在確認
if [ ! -f "$SA_KEY_FILE" ]; then
    handle_error 1 "Service account key file $SA_KEY_FILE not found."
fi

log $LOG_LEVEL_INFO "Project ID: $PROJECT_ID"
log $LOG_LEVEL_INFO "VPC Name: $VPC_NAME"
log $LOG_LEVEL_INFO "Subnet Name: $SUBNET_NAME"
log $LOG_LEVEL_INFO "Region: $REGION"
log $LOG_LEVEL_INFO "Machine Type: $MACHINE_TYPE"
log $LOG_LEVEL_INFO "Service Account Email: $SERVICE_ACCOUNT_EMAIL"

# 利用可能なゾーンのリストを取得
ZONES=$(gcloud compute zones list --filter="region:($REGION)" --format="value(name)")
ZONE=$(echo "$ZONES" | shuf -n 1)
log $LOG_LEVEL_INFO "Selected Zone: $ZONE"

# スタートアップスクリプトの作成
cat << EOF > startup-script.sh
#!/bin/bash
exec > >(tee /var/log/startup-script.log) 2>&1
echo "Startup script started at $(date)"

# データディスクのセットアップ
DEVICE_NAME="/dev/sdb"
MOUNT_POINT="/mnt/disks/data"

if ! grep -qs '\$MOUNT_POINT' /proc/mounts; then
    echo "Setting up data disk..."
    sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard \$DEVICE_NAME
    sudo mkdir -p \$MOUNT_POINT
    sudo mount -o discard,defaults \$DEVICE_NAME \$MOUNT_POINT
    sudo chmod a+w \$MOUNT_POINT
    echo UUID=\$(sudo blkid -s UUID -o value \$DEVICE_NAME) \$MOUNT_POINT ext4 discard,defaults,nofail 0 2 | sudo tee -a /etc/fstab
    echo "Data disk setup completed."
else
    echo "Data disk already mounted."
fi

# Dockerのインストール
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Dockerデータディレクトリの設定
    sudo mkdir -p \$MOUNT_POINT/docker
    sudo tee /etc/docker/daemon.json > /dev/null <<EOT
{
    "data-root": "\$MOUNT_POINT/docker"
}
EOT
    sudo systemctl stop docker
    sudo systemctl stop docker.socket
    sudo systemctl daemon-reload
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker \$USER
    sudo chmod 666 /var/run/docker.sock
else
    echo "Docker is already installed."
fi

echo "Startup script completed at $(date)"
EOF

log $LOG_LEVEL_INFO "Creating VM instance"
# インスタンスの作成
gcloud compute instances create $INSTANCE_NAME \
    --project=$PROJECT_ID \
    --zone=$ZONE \
    --machine-type=$MACHINE_TYPE \
    --network-interface=network=$VPC_NAME,subnet=$SUBNET_NAME \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account=$SERVICE_ACCOUNT_EMAIL \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --create-disk=auto-delete=yes,boot=yes,device-name=$INSTANCE_NAME,image=projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-v20240808,mode=rw,size=$BOOT_DISK_SIZE,type=pd-balanced \
    --create-disk=auto-delete=yes,device-name=$INSTANCE_NAME-data,mode=rw,size=$DATA_DISK_SIZE,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --reservation-affinity=any \
    --metadata-from-file=startup-script=startup-script.sh

log $LOG_LEVEL_INFO "VM instance $INSTANCE_NAME created. Waiting for SSH to be ready..."

# SSHが利用可能になるまで待機
MAX_RETRIES=20
RETRY_INTERVAL=30
for i in $(seq 1 $MAX_RETRIES); do
    if gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="echo SSH is ready" --quiet; then
        log $LOG_LEVEL_INFO "SSH is now available for $INSTANCE_NAME."
        break
    else
        log $LOG_LEVEL_INFO "Waiting for SSH to become available... Attempt $i of $MAX_RETRIES"
        if [ $i -eq $MAX_RETRIES ]; then
            log $LOG_LEVEL_ERROR "Timed out waiting for SSH to become available."
            exit 1
        fi
        sleep $RETRY_INTERVAL
    fi
done

# サービスアカウントキーファイルの転送
log $LOG_LEVEL_INFO "Transferring service account key file..."
gcloud compute scp $SA_KEY_FILE $INSTANCE_NAME:~/sa-key.json --zone=$ZONE

# キーファイルの権限を設定
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="chmod 600 ~/sa-key.json"

log $LOG_LEVEL_INFO "Service account key file transferred and permissions set."

# 起動スクリプトの完了を待つ
log $LOG_LEVEL_INFO "Waiting for startup script to complete..."
MAX_STARTUP_WAIT=1200  # 20分
STARTUP_CHECK_INTERVAL=60  # 1分ごとにチェック
startup_wait_time=0

while [ $startup_wait_time -lt $MAX_STARTUP_WAIT ]; do
    startup_status=$(gcloud compute instances get-serial-port-output $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID | grep "Startup script completed")
    if [[ ! -z "$startup_status" ]]; then
        log $LOG_LEVEL_INFO "Startup script completed successfully."
        break
    fi
    log $LOG_LEVEL_INFO "Startup script still running. Waiting..."
    sleep $STARTUP_CHECK_INTERVAL
    startup_wait_time=$((startup_wait_time + STARTUP_CHECK_INTERVAL))
done

if [ $startup_wait_time -ge $MAX_STARTUP_WAIT ]; then
    log $LOG_LEVEL_ERROR "Startup script did not complete within the expected time. Please check the instance logs."
    exit 1
fi

log $LOG_LEVEL_INFO "VM instance $INSTANCE_NAME setup completed."
log $LOG_LEVEL_INFO "Note: To use Docker without sudo, SSH into the instance and run 'newgrp docker' or log out and log back in."
