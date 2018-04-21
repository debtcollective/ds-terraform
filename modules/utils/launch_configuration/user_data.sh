#!/bin/bash
# Register instance with ECS cluster
echo ECS_CLUSTER=${cluster_name} > /etc/ecs/ecs.config
export ENVIRONMENT=${environment}

# Tools
sudo yum install htop -y

# Create swap file
sudo fallocate -l 1G /swapfile
ls -lh /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf
