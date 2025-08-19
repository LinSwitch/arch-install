#!/bin/bash
# arch-install.sh
# Clean Arch Linux installation: Btrfs + LUKS2 + systemd-boot

set -euo pipefail

# ===============================
# CHECK ENVIRONMENT
# ===============================
[[ "$(id -u)" -ne 0 ]] && { echo "Run script as root"; exit 1; }
[[ ! -d /sys/firmware/efi ]] && { echo "UEFI not detected"; exit 1; }

# ===============================
# VARIABLES (set here or leave empty for interactive input)
# ===============================
HOSTNAME="${HOSTNAME:-}"
USERNAME="${USERNAME:-}"
ROOTPASS="${ROOTPASS:-}"
USERPASS="${USERPASS:-}"
TIMEZONE="Europe/Moscow"
LOCALE="en_US.UTF-8"
SWAP_SIZE=4G

# ===============================
# INTERACTIVE INPUT
# ===============================
if [[ -z "$HOSTNAME" ]]; then
    read -rp "Enter hostname: " HOSTNAME
fi

if [[ -z "$USERNAME" ]]; then
    read -rp "Enter username: " USERNAME
fi

# Root password
if [[ -z "$ROOTPASS" ]]; then
    while true; do
        read -s -rp "Enter root password: " ROOTPASS
        echo
        read -s -rp "Repeat root password: " ROOTPASS2
        echo
        [[ "$ROOTPASS" == "$ROOTPASS2" && -n "$ROOTPASS" ]] && break
        echo "Passwords do not match or empty. Try again."
    done
fi

# User password
if [[ -z "$USERPASS" ]]; then
    while true; do
        read -s -rp "Enter password for $USERNAME: " USERPASS
        echo
        read -s -rp "Repeat password for $USERNAME: " USERPASS2
        echo
        [[ "$USERPASS" == "$USERPASS2" && -n "$USERPASS" ]] && break
        echo "Passwords do not match or empty. Try again."
    done
fi


# ===============================
# SELECT DISK
# ===============================
mapfile -t DISKS < <(lsblk -d -p -n -o NAME,SIZE,MODEL | grep -vE 'loop|zram')
PS3="Select disk: "
select d in "${DISKS[@]}"; do
    [[ -n $d ]] && { DISK=${d%% *}; break; }
done
echo "⚠️  ALL DATA on $DISK will be erased!"
read -rp "Type 'yes' to continue: " confirm
[[ "$confirm" != "yes" ]] && { echo "Aborted."; exit 1; }

# ===============================
# PARTITIONING
# ===============================
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI "$DISK"
sgdisk -n 2:0:0  -t 2:8300 -c 2:ROOT "$DISK"

# ===============================
# LUKS ENCRYPTION
# ===============================
cryptsetup luksFormat --perf-no_read_workqueue --perf-no_write_workqueue --iter-time 2000 "${DISK}2"
cryptsetup open --allow-discards "${DISK}2" cryptroot

# ===============================
# BTRFS SUBVOLUMES
# ===============================
mkfs.btrfs -L ArchRoot /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
for vol in @ @home @snapshots @log @pkg @tmp @opt @swap; do
    btrfs subvolume create "/mnt/$vol"
done
umount /mnt

# ===============================
# MOUNT SUBVOLUMES
# ===============================
mount_opts="noatime,ssd,discard=async,compress=zstd"
special_opts="nodatacow,compress=no"
root_dev="/dev/mapper/cryptroot"

mount -o "$mount_opts,subvol=@" "$root_dev" /mnt

declare -A subvolumes=( 
    [@home]="/mnt/home" 
    [@snapshots]="/mnt/.snapshots" 
    [@log]="/mnt/var/log" 
    [@opt]="/mnt/opt" 
)
declare -A special_subvols=( 
    [@pkg]="/mnt/var/cache/pacman/pkg" 
    [@tmp]="/mnt/var/tmp" 
    [@swap]="/mnt/.swap" 
)

mkdir -p /mnt/boot "${subvolumes[@]}" "${special_subvols[@]}"

for sv in "${!subvolumes[@]}"; do
    mount -o "$mount_opts,subvol=$sv" "$root_dev" "${subvolumes[$sv]}"
done

for sv in "${!special_subvols[@]}"; do
    mount -o "$special_opts,subvol=$sv" "$root_dev" "${special_subvols[$sv]}"
    chattr +C "${special_subvols[$sv]}" 2>/dev/null || true
done

# ===============================
# EFI PARTITION
# ===============================
mkfs.fat -F32 -n EFI "${DISK}1"
mount "${DISK}1" /mnt/boot

# ===============================
# SCREATE SWAPFILE
# ===============================
swapfile="/mnt/.swap/swapfile"
btrfs filesystem mkswapfile --size "$SWAP_SIZE" $swapfile
swapon $swapfile

# ===============================
# UPDATE MIRRORS
# ===============================
echo "Updating mirrorlist..."
reflector -c Russia -a 6 --sort rate --save /etc/pacman.d/mirrorlist

# ===============================
# PACSTRAP
# ===============================
pacstrap -K /mnt base linux linux-firmware linux-headers \
    btrfs-progs sudo vim nano networkmanager

# ===============================
# FSTAB
# ===============================
genfstab -U /mnt >> /mnt/etc/fstab
echo "/.swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab

# ===============================
# CHROOT CONFIGURATION
# ===============================
UUID_CRYPT=$(blkid -s UUID -o value "${DISK}2")
arch-chroot /mnt /bin/bash <<EOF
set -e

# Timezone & locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<H
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
H

# Root password
echo "root:$ROOTPASS" | chpasswd --crypt-method SHA512

# User
useradd -m -G wheel,storage,power,audio,video $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd --crypt-method SHA512
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

# Initramfs
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Bootloader
bootctl install
cat > /boot/loader/loader.conf <<LOADER
default arch
timeout 3
console-mode max
editor no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options rd.luks.name=${UUID_CRYPT}=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard rd.vconsole.keymap=us rw
ENTRY

# Enable NetworkManager
systemctl enable NetworkManager

EOF

# ===============================
# FINISH
# ===============================
umount -R /mnt
cryptsetup close cryptroot
echo -e "\n✅ Installation complete!"
echo "1. Reboot the system"
echo "2. After login: sudo pacman -Syu"
