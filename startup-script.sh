#!/bin/bash
exec > >(tee /var/log/startup-script.log) 2>&1
echo "Startup script started at Fri Aug 16 10:11:20 AM UTC 2024"

# データディスクのセットアップ
DEVICE_NAME="/dev/sdb"
MOUNT_POINT="/mnt/disks/data"

if ! grep -qs '$MOUNT_POINT' /proc/mounts; then
    echo "Setting up data disk..."
    sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard $DEVICE_NAME
    sudo mkdir -p $MOUNT_POINT
    sudo mount -o discard,defaults $DEVICE_NAME $MOUNT_POINT
    sudo chmod a+w $MOUNT_POINT
    echo UUID=$(sudo blkid -s UUID -o value $DEVICE_NAME) $MOUNT_POINT ext4 discard,defaults,nofail 0 2 | sudo tee -a /etc/fstab
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
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Dockerデータディレクトリの設定
    sudo mkdir -p $MOUNT_POINT/docker
    sudo tee /etc/docker/daemon.json > /dev/null <<EOT
{
    "data-root": "$MOUNT_POINT/docker"
}
EOT
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    sudo chmod 666 /var/run/docker.sock
else
    echo "Docker is already installed."
fi

echo "Startup script completed at Fri Aug 16 10:11:20 AM UTC 2024"
