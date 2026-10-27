#!/bin/bash
set -euo pipefail
trap 'echo "Command failed: $BASH_COMMAND"' ERR

main () {
  check_platform
  check_networking
  while true; do
    get_hostname
    get_timezone
    get_locale
    get_user
    verify_disk_deletion
    verify_info && break
  done
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
###    SCRIPT FUNCTIONS   ###
#############################

# This function checks that the user provided info is what they are wanting.
verify_info () {
  echo "Hostname: $system_hostname"
  if [[ "${create_user_input^^}" == "Y" ]]; then
    echo "Username (root disabled): $username"
  else
    echo "Username (no local user): $root"
  fi
  echo "Timezone: $time_zone"
  echo "Locale: $locale"
  echo "Disk: $DISK"
  read -p "Is the information above correct?: " correct_info
  if [[ "${correct_info^^}" = "Y" ]]; then
    read -p "Proceed with install?: " proceed_install
    if [[ "${proceed_install^^}" = "Y" ]]; then
      return 0
    elif [[ "${proceed_install^^}" = "N" ]]; then
      echo "Canceling..."
      exit
    fi
  elif [[ "${correct_info^^}" = "N" ]]; then
    return 1
  fi
}

#############################
###     SYSTEM CHECKS     ###
#############################

# THis function verifies that the system is booted in UEFI mode.
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

# This function verifies that the device is connected to internet.
check_networking() {
    if ping -c1 archlinux.org; then
        echo "Network connectivity confirmed."
    else
        echo "No network connection."
        exit 1
    fi
}

#############################
###       DISK SETUP      ###
#############################

# This function verifies the disk the user wants to install on, and verifies that the disks exists.
verify_disk_deletion () {
  while true; do
    while true; do
      lsblk
      read -p "Enter the disk identifier to install Arch Linux. THIS DISK WILL BE WIPED. (e.g., /dev/sdX): " DISK
      if ! lsblk -dn -o TYPE "$DISK"; then
        echo "Invalid block device."
        continue
      elif [[ "$(lsblk -dn -o TYPE "$DISK")" != "disk" ]]; then
        echo "Please select a whole disk."
        continue
      else
        break
      fi
    done
    while true; do
      read -p 'ARE YOU SURE YOU WANT TO WIPE THIS DISK? ALL DATA WILL BE DELETED. "Y" WILL CONTINUE, "N" WILL GO BACK TO DEVICE SELECTION: ' verify_wipe_disk
      if [[ "${verify_wipe_disk^^}" == "Y" ]]; then
        return
      elif [[ "${verify_wipe_disk^^}" == "N" ]]; then
        continue 2
      fi
      echo "Invalid input, try again"
    done
  done
}

# This device wipes and mounts the selected disk.
partition_disk () {
  wipefs -af "$DISK"
  sgdisk --zap-all "$DISK"
  sfdisk "$DISK" <<'EOF'
  label: gpt

  size=1G, type=uefi
  size=8G, type=swap
  type=linux
EOF
    
  partprobe "$DISK"
  udevadm settle
  if [[ "$DISK" =~ (nvme|mmcblk) ]]; then
    part_suffix="p"
  else
    part_suffix=""
  fi
  mkfs.fat -F32 "${DISK}${part_suffix}"1
  mkswap "${DISK}${part_suffix}"2
  mkfs.ext4 "${DISK}${part_suffix}"3
  mount "${DISK}${part_suffix}"3 /mnt
  mount --mkdir "${DISK}${part_suffix}"1 /mnt/boot
  swapon "${DISK}${part_suffix}"2
}

#############################
###      SYSTEM SETUP     ###
#############################

# This function gathers what hostname the user wants, and verifies that it is a "legal" hostname.
get_hostname () {
  while true; do
    read -p "Enter your desired hostname (Default > archlinux): " hostname_input
    system_hostname=${hostname_input:-archlinux}
    if [[ ${#system_hostname} -gt 63 ]]; then
      echo "Hostname must be 63 characters or fewer."
      continue
    fi
    if [[ ! "$system_hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
      echo "Invalid hostname."
      echo "Only letters, numbers, periods, and hyphens are allowed."
      echo "Hostname cannot begin or end with a period or hyphen."
      continue
    fi
    break
  done
}

# This function gathers the users desired timezone and verifies its existence.
get_timezone () {
  while true; do
    read -p "Enter time zone (Default > America/New_York): " tz_input
    time_zone=${tz_input:-America/New_York}
    if [[ -f "/usr/share/zoneinfo/$time_zone" ]]; then
      break
    else
      echo "Invalid input. Try again."
    fi
  done
}

# This function gathers the users desired locale, and verifies it exists.
get_locale () {
  while true; do
    read -p "Enter UTF-8 locale (Default > en_US): " locale_input
    locale=${locale_input:-en_US}
    if grep -q "^#\?${locale}\.UTF-8" /etc/locale.gen; then
      break
    else
      echo "Invalid input. Try again."
    fi
  done
}

# This function install the base, necessary componenets to run arch linux.
install_system () {
  echo "Installing base system..."
  pacstrap -K /mnt base linux linux-firmware nano networkmanager vi sudo grub efibootmgr base-devel git
  arch-chroot /mnt systemctl enable NetworkManager
  echo "Base system installed."
}

# This function generates the fstab file.
create_fstab () {
  echo "Generating file /etc/fstab."
  genfstab -U /mnt > /mnt/etc/fstab
  echo "File /etc/fstab generated."
}

# This function handles the localization of the system.
localize_system () {
  echo "Setting locales..."
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$time_zone" /etc/localtime
  arch-chroot /mnt hwclock --systohc
  arch-chroot /mnt sed -i "/${locale}\.UTF-8/s/^#\s*//" /etc/locale.gen
  arch-chroot /mnt locale-gen
  echo "LANG=${locale}.UTF-8" > /mnt/etc/locale.conf
  echo 'KEYMAP=us' > /mnt/etc/vconsole.conf
  echo "Enabling NTP..."
  arch-chroot /mnt timedatectl set-ntp true
  echo "NTP enabled."
  echo "Locales set."
}

# This function sets the device hostname.
set_hostname () {
  echo "Setting hostname..."
  echo "$system_hostname" > /mnt/etc/hostname
  echo "Hostname set."
}

# This function installs the grub bootloader.
install_grub () {
  echo "Installing grub..."
  if [[ "$platform_size" == "64" ]]; then
    arch-chroot /mnt grub-install --removable --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  elif [[ "$platform_size" == "32" ]]; then
    arch-chroot /mnt grub-install --removable --target=i386-efi --efi-directory=/boot --bootloader-id=GRUB
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
  echo "Grub installed."
}

# This function unmounts partitions and restarts the device.
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

# This function gathers whether the user wants to setup root or a sudo user and verifies the "legality" of usernames and passwords.
get_user () {
  while true; do
    read -p "Do you want to create a local user and disable root login? (Y/N): " create_user_input
    if [[ "${create_user_input^^}" == "Y" ]]; then
      while true; do
        read -p "Enter your desired username (Default > local.user): " username_input
        username=${username_input:-local.user}
        if [[ ! "$username" =~ ^[a-z_][a-z0-9._-]{0,31}$ ]] || [[ "$username" =~ [.-]$ ]]; then
          echo "Invalid username."
          echo "Usernames must:"
          echo "  - Start with a lowercase letter or underscore"
          echo "  - Contain only lowercase letters, numbers, ., _, or -"
          echo "  - Not end with . or -"
          echo "  - Be 32 characters or fewer"
          continue
        fi
        password_confirm
        break
      done
    break
    elif [[ "${create_user_input^^}" == "N" ]]; then
      echo "Using root user only."
      password_confirm
      break
    else
      echo "Invalid input. Try again"
    fi
  done
}

# This function gathers the user password and verifies that they match.
password_confirm () {
    while true; do
      read -s -p "Enter your desired password: " password_input_1
      echo
      read -s -p "Confirm your desired password: " password_input_2
      echo
      if [[ "$password_input_1" == "$password_input_2" ]]; then
        echo "Passwords match."
        password="$password_input_1"
        unset password_input_1 password_input_2
        break
      else
        echo "Password do not match. Try again."
      fi
    done
}

# This function sets up the root user for use.
setup_root () {
  echo "root:$password" | arch-chroot /mnt chpasswd
}

# This function sets up a sudo user for use.
create_user () {
  arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"
  echo "$username:$password" | arch-chroot /mnt chpasswd
  arch-chroot /mnt sed -i 's/^# *\(%wheel ALL=(ALL:ALL) ALL\)$/\1/' /etc/sudoers
  arch-chroot /mnt passwd -d root
  arch-chroot /mnt passwd --lock root
}

#############################
###      DE INSTALLS      ###
#############################
niri-install() {
  arch-chroot /mnt 'pacman -S lightdm lightdm-gtk-greeter alacritty niri
    systemctl enable lightdm
  '
}

kde-install() {
  arch-chroot /mnt 'pacman -S --noconfirm plasma konsole
  systemctl enable sddm
  '
}

gnome-install() {
  arch-chroot /mnt 'pacman -S --noconfirm gnome
  systemctl enable gdm
  '
}
#############################
###      AUR INSTALLS     ###
#############################
paru-install() {
  arch-chroot /mnt su - "$username" -c 'git clone https://aur.archlinux.org/paru.git
    cd ~/paru
    makepkg -s --noconfirm
  '
  arch-chroot /mnt 'pacman -U --noconfirm /home/'"$username"'/paru/paru-*
  rm -rf /home/'"$username"'/paru
  '
  arch-chroot /mnt su - "$username" -c 'paru --gendb'
}

yay-install() {
  arch-chroot /mnt su  "$username" -c 'git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -s
  '
  arch-chroot /mnt 'pacman -U --noconfirm /home/'"$username"'/yay/yay-*
  rm -rf /home/'"$username"'/yay
  '
}

main
