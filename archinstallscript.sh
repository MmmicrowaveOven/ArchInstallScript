#!/bin/bash

platform_size=$(cat /sys/firmware/efi/fw_platform_size)

if [[ "$platform_size" == "64" ]]; then
  echo "this is 64"
else
  echo "this is not 64"
fi

timedatectl

lsblk

read -p "Enter the disk identifier (e.g., /dev/sdX): " DISK

wipefs -af $DISK

sfdisk $DISK <<'EOF'
label: gpt

size=1G, type=uefi
size=8G, type=swap
type=linux
EOF

partprobe $DISK

if [[ "$DISK" == "nvme" ]]; then
  mkfs.fat -F32 ${DISK}p1
  mkswap ${DISK}p2
  mkfs.ext4 ${DISK}p3
elif [[ "DISK" == "sd" ]]; then
  mkfs.fat -F32 ${DISK}1
  mkswap ${DISK}2
  mkfs.ext4 ${DISK}3
else
  exit
fi
