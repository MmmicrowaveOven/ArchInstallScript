#!/bin/bash
set -euo pipefail
trap 'echo "Installation failed on line $LINENO."' ERR

main () {
  check_platform
  get_hostname
  get_timezone
  get_locale
  get_user
  verify_disk_deletion
  partition_disk
  install_system
  create_fstab
  localize_system
  set_hostname
  if [[ "${create_user_input^^}" == "Y" ]]; then
    create_user
  elif [[ "${create_user_input^^}" == "N" ]]; then
    setup_root
  fi
  install_grub
  cleanup
}

#############################
###     SYSTEM CHECKS     ###
#############################

check_platform () {
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

#############################
###       DISK SETUP      ###
#############################

verify_disk_deletion () {
  while true; do
    while true; do
      lsblk
      read -p "Enter the disk identifier to install Arch Linux. THIS DISK WILL BE WIPED. (e.g., /dev/sdX): " DISK
      if ! lsblk -dn -o TYPE "$DISK" >/dev/null 2>&1; then
        echo "Invalid block device."
        continue
      elif [[ "$(lsblk -dn -o TYPE "$DISK")" != "disk" ]]; then
        echo "Please select a whole disk."
        continue
      elif [[ -b "$DISK" ]]; then
        break
      fi
    done
    while true; do
      read -p 'ARE YOU SURE YOU WANT TO WIPE THIS DISK? ALL DATA WILL BE DELETED. "Y" WILL CONTINUE, "N" WILL GO BACK TO DEVICE SELECTION: ' verify_wipe_disk
      if [[ "${verify_wipe_disk^^}" == "Y" ]]; then
        partition_disk
        return
      elif [[ "${verify_wipe_disk^^}" == "N" ]]; then
        continue 2
      fi
      echo "Invalid input, try again"
    done
  done
}

partition_disk () {
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
    mount "${DISK}"p3 /mnt > /dev/null
    mount --mkdir "${DISK}"p1 /mnt/boot > /dev/null
    swapon "${DISK}"p2 > /dev/null
  elif [[ "$DISK" =~ sd ]]; then
    mkfs.fat -F32 "${DISK}"1 > /dev/null
    mkswap "${DISK}"2 > /dev/null
    mkfs.ext4 "${DISK}"3 > /dev/null
    mount "${DISK}"3 /mnt > /dev/null
    mount --mkdir "${DISK}"1 /mnt/boot > /dev/null
    swapon "${DISK}"2 > /dev/null
  else
    exit
  fi
}

#############################
###      SYSTEM SETUP     ###
#############################

get_hostname () {
  read -p "Enter your desired hostname (Default > archlinux): " hostname_input
  system_hostname=${hostname_input:-archlinux}
}

get_timezone () {
  read -p "Enter time zone (Default > America/New_York): " tz_input
  time_zone=${tz_input:-America/New_York}
}

get_locale () {
  read -p "Enter UTF-8 locale (Default > en_US): " locale_input
  locale=${locale_nput:-en_US}
}

install_system () {
  echo "Installing base system..."
  pacstrap -K /mnt base linux linux-firmware nano networkmanager vi sudo grub efibootmgr  > /dev/null
  arch-chroot /mnt systemctl enable NetworkManager > /dev/null
  echo "Base system installed."
}

create_fstab () {
  echo "Generating file /etc/fstab."
  genfstab -U /mnt > /mnt/etc/fstab
  echo "File /etc/fstab generated."
}

localize_system () {
  echo "Setting locales..."
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$time_zone" /etc/localtime > /dev/null
  arch-chroot /mnt hwclock --systohc > /dev/null
  arch-chroot /mnt sed -i "/${locale}\.UTF-8/s/^#\s*//" /etc/locale.gen
  arch-chroot /mnt locale-gen > /dev/null
  echo "LANG=${locale}.UTF-8" > /mnt/etc/locale.conf
  echo 'KEYMAP=us' > /mnt/etc/vconsole.conf
  echo "Enabling NTP..."
  arch-chroot /mnt timedatectl set-ntp true
  echo "NTP enabled."
  echo "Locales set."
}

set_hostname () {
  echo "Setting hostname..."
  echo "$system_hostname" > /mnt/etc/hostname
  echo "Hostname set."
}

install_grub () {
  echo "Installing grub..."
  if [[ "$platform_size" == "64" ]]; then
    arch-chroot /mnt grub-install --removable --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB > /dev/null
  elif [[ "$platform_size" == "32" ]]; then
    arch-chroot /mnt grub-install --removable --target=i386-efi --efi-directory=/boot --bootloader-id=GRUB > /dev/null
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg > /dev/null
  echo "Grub installed."
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

#############################
###       USER SETUP      ###
#############################

get_user () {
  read -p "Do you want to create a local user and disable root login? (Y/N): " create_user_input
  if [[ "${create_user_input^^}" == "Y" ]]; then
    read -p "Enter your desired username (Default > local.user): " username_input
    username=${username_input:-local.user}
    password_confirm
  elif [[ "${create_user_input^^}" == "N" ]]; then
    echo "Using root user only."
    password_confirm
  fi
}

password_confirm () {
    while true; do
      read -s "Enter your desired password: " password_input_1
      read -s "Confirm your desired password: " password_input_2
      if [[ "$password_input_1" == "$password_input_2" ]]; then
        echo "Passwords match."
        root_password="$password_input_1"
        break
      else
        echo "Password do not match. Try again."
    done
}

setup_root () {
  arch-chroot /mnt echo "$root_password" | passwd --stdin
}

create_user () {
  arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"
  arch-chroot /mnt echo "$user_password" | passwd "$username" --stdin
  arch-chroot /mnt sed -i 's/^# *\(%wheel ALL=(ALL:ALL) ALL\)$/\1/' /etc/sudoers
  arch-chroot /mnt sed -i '/^[[:space:]]*#/b; /^[[:space:]]*$/b; s/^/# /' /etc/securetty
}

main
