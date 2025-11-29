#!/bin/bash

USERNAME="code"

# Update system
sudo apt-get update
sudo apt-upgrade -y

# Install QEMU Guest Agent
sudo apt install -y qemu-guest-agent

# Install dependencies
sudo apt-get install ca-certificates curl sudo zsh build-essential rsync qemu-guest-agent -y

# Install Docker
sudo curl -sSL https://get.docker.com/ | sh

# Update system
sudo apt-get upgrade -y
sudo apt-get autoremove -y

# Add user to docker group
sudo groupadd docker
sudo usermod -aG docker $USERNAME

# change DNSStubListener=no in /etc/systemd/resolved.conf
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved

# Restart docker
sudo systemctl restart docker

# Reboot the system
sudo reboot
