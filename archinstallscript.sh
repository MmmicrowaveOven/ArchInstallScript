#!/bin/bash
set -euo pipefail

main () {
  verify_platform
  gather_input
  verify_disk_deletion
  timedatectl set-ntp true
  system_prep
  cleanup
}

verify_platform () {
  if [[ ! -f /sys/firmware/efi/fw_platform_size ]]; then
    echo "This system is not running in UEFI mode. Press any key to reboot and try again."
    read -s -n1
    echo "Rebooting..."
    sleep 2
    reboot
  fi
  platform_size=$(< /sys/firmware/efi/fw_platform_size)
  if [[ "$platform_size" == "64" ]]; then
    echo "This system is running in 64-bit UEFI mode."
  elif [[ "$platform_size" == "32" ]]; then
    echo "This system is running in 32-bit UEFI mode."
  fi
}

gather_input () {
  read -p "Enter your desired hostname (Default > archlinux): " input
  system_hostname=${input:-archlinux}
  read -p "Enter time zone (Default > America/New_York): " input
  time_zone=${input:-America/New_York}
  read -p "Enter UTF-8 locale (Default > en_US): " input
  locale=${input:-en_US}
}

verify_disk_deletion () {
  while true; do
    while true; do
      lsblk
      read -p "Enter the disk identifier to install Arch Linux. THIS DISK WILL BE WIPED. (e.g., /dev/sdX): " DISK
      if ! lsblk -dn -o TYPE "$DISK" >/dev/null 2>&1; then
        echo "Invalid block device."
        continue
      fi

      if [[ "$(lsblk -dn -o TYPE "$DISK")" != "disk" ]]; then
        echo "Please select a whole disk."
        continue
      fi
      elif [[ -b "$DISK" ]]; then
        break
      fi
    done
    while true; do
      read -p 'ARE YOU SURE YOU WANT TO WIPE THIS DISK? ALL DATA WILL BE DELETED. "Y" WILL CONTINUE, "N" WILL GO BACK TO DEVICE SELECTION: ' verify_wipe_disk
      if [[ "${verify_wipe_disk^^}" == "Y" ]]; then
        wipe_disk
        return
      elif [[ "${verify_wipe_disk^^}" == "N" ]]; then
        continue 2
      fi
      echo "Invalid input, try again"
    done
  done
}

wipe_disk () {
  wipefs -af "$DISK" > /dev/null
  sfdisk "$DISK" <<'EOF'
  label: gpt

  size=1G, type=uefi
  size=8G, type=swap
  type=linux
EOF
    
  partprobe "$DISK" > /dev/null
  udevadm settle
  if [[ "$DISK" =~ nvme ]]; then
    mkfs.fat -F32 "${DISK}"p1 > /dev/null
    mkswap "${DISK}"p2 > /dev/null
    mkfs.ext4 "${DISK}"p3 > /dev/null
  elif [[ "$DISK" =~ sd ]]; then
    mkfs.fat -F32 "${DISK}"1 > /dev/null
    mkswap "${DISK}"2 > /dev/null
    mkfs.ext4 "${DISK}"3 > /dev/null
  else
    exit
  fi
  
  if [[ "$DISK" =~ nvme ]]; then
    mount "${DISK}"p3 /mnt > /dev/null
    mount --mkdir "${DISK}"p1 /mnt/boot > /dev/null
    swapon "${DISK}"p2 > /dev/null
  elif [[ "$DISK" =~ sd ]]; then
    mount "${DISK}"3 /mnt > /dev/null
    mount --mkdir "${DISK}"1 /mnt/boot > /dev/null
    swapon "${DISK}"2 > /dev/null
  else
    exit
  fi
}

system_prep () {
  echo "Installing base system..."
  pacstrap -K /mnt base linux linux-firmware nano networkmanager vi sudo grub efibootmgr  > /dev/null
  arch-chroot /mnt systemctl enable NetworkManager > /dev/null
  echo "Base system installed."
  echo "Generating file /etc/fstab."
  genfstab -U /mnt > /mnt/etc/fstab
  echo "File /etc/fstab generated."
  echo "Setting locales..."
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$time_zone" /etc/localtime > /dev/null
  arch-chroot /mnt hwclock --systohc > /dev/null
  arch-chroot /mnt sed -i \
    "/^#${locale}\.UTF-8 UTF-8$/s/^#//" \
    /etc/locale.gen
  arch-chroot /mnt locale-gen > /dev/null
  echo "LANG=${locale}.UTF-8" > /mnt/etc/locale.conf
  echo 'KEYMAP=us' > /mnt/etc/vconsole.conf
  echo "Locales set."
  echo "Setting hostname..."
  echo "$system_hostname" > /mnt/etc/hostname
  echo "Hostname set."
  echo "Installing grub..."
  if [[ "$platform_size" == "64" ]]; then
    arch-chroot /mnt grub-install --removable --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB > /dev/null
  elif [[ "$platform_size" == "32" ]]; then
    arch-chroot /mnt grub-install --removable --target=i386-efi --efi-directory=/boot --bootloader-id=GRUB > /dev/null
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg > /dev/null
  echo "Grub installed."
  echo "Set root user password:"
  arch-chroot /mnt passwd
}

cleanup () {
  swapoff -a
  umount -R /mnt
  sync
  echo "Remove media then press enter to reboot."
  read -s -n 1
  echo "Rebooting..."
  sleep 2
  reboot
}

main
