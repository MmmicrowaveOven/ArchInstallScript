#!/bin/bash

main () {
  verify_platform
  gather_input
  verify_disk_deletion
  wipe_disk
  timedatectl
  system_prep
  cleanup
}

verify_platform () {
  platform_size=$(cat /sys/firmware/efi/fw_platform_size)
  if [[ "$platform_size" == "64" ]]; then
    echo "This system is running in 64-bit UEFI mode."
  elif [[ "$platform_size" == "32" ]]; then
    echo "This system is running in 32-bit UEFI mode."
  else
    echo "This system is not running in UEFI mode. Press any key to reboot and try again."
    read -s -n 1
    echo "Rebooting..."
    sleep 2
    reboot
  fi
}

gather_input () {
  hostname="archlinux"
  time_zone="America/New_York"
  locale="en_US"
  read -p "Enter your desired hostname (Default > archlinux): " hostname
  read -p "Enter time zone (Default >  America/New_York): " time_zone
  read -p "Enter UTF-8 locale (Default > en_US): " locale
}

verify_disk_deletion () {
  lsblk
  read -p "Enter the disk identifier to install Arch Linux. THIS DISK WILL BE WIPED. (e.g., /dev/sdX): " DISK
  while true; do
    read -p 'ARE YOU SURE YOU WANT TO WIPE THIS DISK? ALL DATA WILL BE DELETED. "Y" WILL CONTINUE, "N" WILL GO BACK TO DEVICE SELECTION' verify_wipe_disk
    if [[ "$verify_wipe_disk" == "Y" ]]; then
      wipe_disk
      break
    elif [[ "$verify_wipe_disk" == "N" ]]; then
      verify_disk_deletion
      break
    fi
    echo "Invalid input, try again"
  done
}

wipe_disk () {
  wipefs -af "$DISK" > /dev/null
  sfdisk "$DISK" <<'EOF'
  label: gpt

  size=1G, type=U
  size=8G, type=swap
  type=linux
EOF
    
  partprobe "$DISK" > /dev/null
  
  if [[ "$DISK" =~ nvme ]]; then
    mkfs.fat -F32 ${DISK}p1 > /dev/null
    mkswap ${DISK}p2 > /dev/null
    mkfs.ext4 ${DISK}p3 > /dev/null
  elif [[ "$DISK" =~ sd ]]; then
    mkfs.fat -F32 ${DISK}1 > /dev/null
    mkswap ${DISK}2 > /dev/null
    mkfs.ext4 ${DISK}3 > /dev/null
  else
    exit
  fi
  
  if [[ "$DISK" =~ nvme ]]; then
    mount ${DISK}p3 /mnt > /dev/null
    mount --mkdir ${DISK}p1 /mnt/boot > /dev/null
    swapon ${DISK}p2 > /dev/null
  elif [[ "$DISK" =~ sd ]]; then
    mount ${DISK}3 /mnt > /dev/null
    mount --mkdir ${DISK}1 /mnt/boot > /dev/null
    swapon ${DISK}2 > /dev/null
  else
    exit
  fi
}

system_prep () {
  echo "Installing base system..."
  pacstrap -K /mnt base linux linux-firmware nano networkmanager vi sudo grub efibootmgr  > /dev/null
  echo "Base system installed."
  echo "Generating file /etc/fstab."
  genfstab -U /mnt >> /mnt/etc/fstab > /dev/null
  echo "File /etc/fstab generated."
  echo "Setting locales..."
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/$time_zone /etc/localtime > /dev/null
  arch-chroot /mnt hwclock --systohc > /dev/null
  arch-chroot /mnt sed -i \
    "/^#${locale}\.UTF-8 UTF-8$/s/^#//" \
    /etc/locale.gen
  arch-chroot /mnt locale-gen > /dev/null
  arch-chroot /mnt bash -c \
    "echo 'LANG=${locale}.UTF-8' > /etc/locale.conf"
  arch-chroot /mnt bash -c "echo 'KEYMAP=us' > /etc/vconsole.conf" > /dev/null
  arch-chroot /mnt sed -i "/^#\?${locale}\.UTF-8 UTF-8$/s/^#//" /etc/locale.gen > /dev/null
  arch-chroot /mnt locale-gen > /dev/null
  arch-chroot /mnt bash -c "echo '$hostname' > /etc/hostname" > /dev/null
  arch-chroot /mnt grub-install --removable --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB > /dev/null
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg > /dev/null
  arch-chroot /mnt passwd
}

cleanup () {
  umount -R /mnt
  echo "Remove media then press enter to reboot."
  read -s -n 1
  echo "Rebooting..."
  sleep 2
  reboot
}

main
