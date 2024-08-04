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
BOOT_DISK_SIZE="10GB"
DATA_DISK_SIZE="200GB"
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

# 特定のUbuntu 20.04 LTS イメージを設定
UBUNTU_IMAGE_PROJECT="ubuntu-os-cloud"
UBUNTU_IMAGE="ubuntu-2004-focal-v20240731"

# サービスアカウントキーファイルの存在確認
if [ ! -f "$SA_KEY_FILE" ]; then
    echo "エラー: サービスアカウントキーファイル $SA_KEY_FILE が見つかりません。"
    exit 1
fi

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

# Dockerのインストール（初回のみ）
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    # Dockerサービスの起動と有効化
    echo "Starting and enabling Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker

    # 現在のユーザーをdockerグループに追加
    echo "Adding current user to docker group..."
    sudo usermod -aG docker \$USER

    # Dockerソケットのパーミッション変更
    echo "Changing Docker socket permissions..."
    sudo chmod 666 /var/run/docker.sock
else
    echo "Docker is already installed."
fi

# サンプルDockerコンテナの起動（例：Nginx）
if ! docker ps -a | grep -q my-nginx; then
    echo "Starting sample Nginx Docker container..."
    docker run -d -p 80:80 --name my-nginx nginx
else
    echo "Nginx container is already running."
fi

# シリアルポートの有効化
if ! grep -q "console=ttyS0" /etc/default/grub; then
    echo "Enabling serial port..."
    sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="console=ttyS0,38400n8"/' /etc/default/grub
    sudo update-grub
else
    echo "Serial port is already enabled."
fi

# tiffファイルの保存先ディレクトリの作成
DEM_DIR="/mnt/disks/data/dem"
sudo mkdir -p \$DEM_DIR
sudo chmod a+w \$DEM_DIR

# フラグファイルの設定
FLAG_FILE="\$DEM_DIR/.tiff_files_downloaded"

# gs://obp-dem/*.tif ファイルのコピー（フラグファイルが存在しない場合のみ）
if [ ! -f "\$FLAG_FILE" ]; then
    echo "Copying .tif files from gs://obp-dem/ to \$DEM_DIR"
    gsutil -m cp gs://obp-dem/*.tif \$DEM_DIR/
    if [ \$? -eq 0 ]; then
        echo "Copy completed successfully."
        # フラグファイルの作成
        touch \$FLAG_FILE
    else
        echo "Error occurred during file copy."
    fi
else
    echo "Tiff files have already been downloaded. Skipping download."
fi

echo "Startup script completed at $(date)"
EOF

# VMインスタンスの作成
gcloud compute instances create $INSTANCE_NAME \
    --project=$OBP_PROJECT_ID \
    --zone=${REGION}-b \
    --machine-type=$MACHINE_TYPE \
    --network-interface=network=$OBP_VPC_NAME,subnet=$OBP_SUBNET_NAME \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account=$OBP_SERVICE_ACCOUNT_EMAIL \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --create-disk=auto-delete=yes,boot=yes,device-name=$INSTANCE_NAME,image-project=$UBUNTU_IMAGE_PROJECT,image=$UBUNTU_IMAGE,mode=rw,size=$BOOT_DISK_SIZE,type=pd-balanced \
    --create-disk=auto-delete=yes,device-name=$INSTANCE_NAME-data,mode=rw,size=$DATA_DISK_SIZE,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=ec-src=vm_add-gcloud \
    --reservation-affinity=any \
    --metadata-from-file=startup-script=startup-script.sh \
    --metadata=serial-port-enable=true

echo "VMインスタンス $INSTANCE_NAME が作成されました。SSHの準備を待っています..."

# インスタンスが完全に起動し、SSHが利用可能になるまで待機
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

# 起動スクリプトの完了を待つ
echo "起動スクリプトの完了を待っています..."
while true; do
    output=$(gcloud compute instances get-serial-port-output $INSTANCE_NAME --zone=${REGION}-b --project=$OBP_PROJECT_ID 2>&1)
    if echo "$output" | grep -q "Startup script completed"; then
        echo "起動スクリプトが完了しました。"
        break
    elif echo "$output" | grep -q "Error occurred during file copy"; then
        echo "ファイルのコピー中にエラーが発生しました。"
        break
    fi
    sleep 10
done

echo "VMインスタンス $INSTANCE_NAME のセットアップが完了しました。"
echo "注意: Dockerをsudoなしで使用するには、インスタンスにSSH接続後に 'newgrp docker' コマンドを実行するか、一度ログアウトして再度ログインしてください。"
