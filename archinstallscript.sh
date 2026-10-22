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

wipefs -af /dev/$DISK
