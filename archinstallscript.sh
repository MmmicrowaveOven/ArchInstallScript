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

wipefs -af "$DISK"

sfdisk "$DISK" <<'EOF'
label: gpt

size=1G, type=U
size=8G, type=swap
type=linux
EOF

partprobe "$DISK"

if [[ "$DISK" =~ nvme ]]; then
  mkfs.fat -F32 ${DISK}p1
  mkswap ${DISK}p2
  mkfs.ext4 ${DISK}p3
elif [[ "$DISK" =~ sd ]]; then
  mkfs.fat -F32 ${DISK}1
  mkswap ${DISK}2
  mkfs.ext4 ${DISK}3
else
  exit
fi

if [[ "$DISK" =~ nvme ]]; then
  mount ${DISK}p3 /mnt
  mount --mkdir ${DISK}p1 /mnt/boot
  swapon ${DISK}p2
elif [[ "$DISK" =~ sd ]]; then
  mount ${DISK}3 /mnt
  mount --mkdir ${DISK}1 /mnt/boot
  swapon ${DISK}2
else
  exit
fi

pacstrap -K /mnt base linux linux-firmware nano networkmanager vi sudo grub efibootmgr

genfstab -U /mnt >> /mnt/etc/fstab

read -p "Enter time zone (e.g., America/New_York): " time_zone

arch-chroot /mnt ln -sf /usr/share/zoneinfo/$time_zone /etc/localtime

arch-chroot /mnt hwclock --systohc

read -p "Enter UTF-8 locale (e.g., en_US): " locale

arch-chroot /mnt sed -i "/^#\?${locale}\.UTF-8 UTF-8$/s/^#//" /etc/locale.gen

arch-chroot /mnt locale-gen

arch-chroot /mnt "echo 'KEYMAP=us' > /etc/vconsole.conf"

arch-chroot /mnt "echo 'LANG=${locale}.UTF-8' > /etc/locale.conf"

read -p "Enter your desired hostname: " hostname

arch-chroot /mnt "echo '$hostname' > /etc/hostname"

arch-chroot /mnt passwd

arch-chroot /mnt grub-install --removable --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

umount -R /mnt

echo "Remove media then press enter to reboot."

read -s -n 1

echo "Rebooting..."

sleep 2

reboot
