#!/bin/bash
# arch-install.sh
# Clean Arch Linux installation: Ext4 + GRUB (no encryption)

set -euo pipefail

# ===============================
# CHECK ENVIRONMENT
# ===============================
[[ "$(id -u)" -ne 0 ]] && { echo "Run script as root"; exit 1; }
[[ ! -d /sys/firmware/efi ]] && { echo "UEFI not detected"; exit 1; }

# ===============================
# VARIABLES (set here or leave empty for interactive input)
# ===============================
HOSTNAME=""
USERNAME=""
ROOTPASS=""
USERPASS=""
TIMEZONE="Europe/Moscow"
LOCALE="en_US.UTF-8"
SWAPFILE_SIZE=4G  

# ===============================
# INTERACTIVE INPUT
# ===============================

# Hostname
if [[ -z "$HOSTNAME" ]]; then
    echo
    echo "=== HOSTNAME SETUP ==="
    while true; do
        read -rp "Enter hostname (lowercase, no spaces): " HOSTNAME
        OLD_HOSTNAME="$HOSTNAME"
        HOSTNAME=$(echo "$HOSTNAME" | tr '[:upper:]' '[:lower:]')   # авто-лоуэркейз
        if [[ "$HOSTNAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
            [[ "$OLD_HOSTNAME" != "$HOSTNAME" ]] && echo "Notice: hostname converted to lowercase: $HOSTNAME"
            break
        else
            echo "Invalid hostname. Use lowercase letters, digits, or hyphens (cannot start/end with hyphen, max 63 chars)."
        fi
    done
fi

# Root password
if [[ -z "$ROOTPASS" ]]; then
    echo
    echo "=== ROOT PASSWORD SETUP ==="
    echo "!!! ROOT PASSWORD WILL BE USED FOR SYSTEM ADMINISTRATION !!!"
    while true; do
        read -s -rp "Enter ROOT password: " ROOTPASS
        echo
        read -s -rp "Repeat ROOT password: " ROOTPASS2
        echo
        [[ "$ROOTPASS" == "$ROOTPASS2" && -n "$ROOTPASS" ]] && break
        echo "Passwords do not match or empty. Try again."
    done
fi

# User name
if [[ -z "$USERNAME" ]]; then
    echo
    echo "=== USERNAME SETUP ==="
    while true; do
        read -rp "Enter username (lowercase, no spaces): " USERNAME
        OLD_USERNAME="$USERNAME"
        USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')   # авто-лоуэркейз
        if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            [[ "$OLD_USERNAME" != "$USERNAME" ]] && echo "Notice: username converted to lowercase: $USERNAME"
            break
        else
            echo "Invalid username. Use lowercase letters, digits, underscore or hyphen (must start with a letter/underscore)."
        fi
    done
fi

# User password
if [[ -z "$USERPASS" ]]; then
    echo
    echo "=== USER PASSWORD SETUP ==="
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
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI "$DISK"          # EFI partition
sgdisk -n 2:0:0 -t 2:8300 -c 2:ROOT "$DISK"             # Root partition

# EFI fat
mkfs.fat -F32 -n EFI "${DISK}1"

# root ext4
mkfs.ext4 -L ArchRoot "${DISK}2"

mount "${DISK}2" /mnt

mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# ===============================
# UPDATE MIRRORS
# ===============================
echo "Updating mirrorlist..."

success=false
for attempt in 1 2; do
    echo "  -> Attempt $attempt: updating mirrors via reflector..."
    if reflector -c Russia,Finland,Germany,Netherlands,Switzerland \
        --protocol https --latest 5 --ipv4 --save /etc/pacman.d/mirrorlist; then
        echo "  -> Success"
        success=true
        break
    else
        echo "  -> Failed to update mirrors"
    fi
done

if [ "$success" != true ]; then
    echo "  -> Using fallback mirrors"
    cat > /etc/pacman.d/mirrorlist <<MIRRORS
Server = https://mirror.pseudoform.org/ \$repo/os/\$arch
Server = https://pkg.fef.moe/archlinux/ \$repo/os/\$arch
Server = https://berlin.mirror.pkgbuild.com/ \$repo/os/\$arch
Server = https://cdnmirror.com/archlinux/ \$repo/os/\$arch
Server = https://mirror.ubrco.de/archlinux/ \$repo/os/\$arch
MIRRORS
fi

# ===============================
# PACSTRAP 
# ===============================
pacstrap /mnt base linux linux-firmware linux-headers \
    sudo vim nano networkmanager grub efibootmgr os-prober

# ===============================
# FSTAB
# ===============================
genfstab -U /mnt >> /mnt/etc/fstab

# ===============================
# CHROOT CONFIGURATION
# ===============================
arch-chroot /mnt /bin/bash <<EOF
set -e

# Timezone & locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf
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

# Swap file
echo "Creating swap file..."
fallocate -l "${SWAPFILE_SIZE}iB" /swapfile
chmod 600 /swapfile
mkswap /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

# Initramfs 
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Bootloader - GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
systemctl enable NetworkManager

EOF

# ===============================
# FINISH
# ===============================
umount -R /mnt
echo -e "\n✅ Installation complete!"
echo "1. Reboot the system: reboot"
echo "2. After login: sudo pacman -Syu"