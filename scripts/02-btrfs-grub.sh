#!/bin/bash
# 02-btrfs-grub.sh
# Clean Arch Linux installation: Btrfs + Grub + auto snapshots
# _     _       _____          _ _       _     
#| |   (_)     /  ___|        (_) |     | |    
#| |    _ _ __ \ `--.__      ___| |_ ___| |__  
#| |   | | '_ \ `--. \ \ /\ / / | __/ __| '_ \ 
#| |___| | | | /\__/ /\ V  V /| | || (__| | | |
#\_____/_|_| |_\____/  \_/\_/ |_|\__\___|_| |_|
#

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
SWAP_SIZE=4G

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
        HOSTNAME=$(echo "$HOSTNAME" | tr '[:upper:]' '[:lower:]')   
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
        USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')   
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
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI "$DISK"
sgdisk -n 2:0:0  -t 2:8300 -c 2:ROOT "$DISK"

# ===============================
# BTRFS SUBVOLUMES
# ===============================
mkfs.btrfs -L ArchRoot "${DISK}2"
mount "${DISK}2" /mnt
for vol in @ @home @log @pkg @tmp @opt @swap; do
    btrfs subvolume create "/mnt/$vol"
done
umount /mnt

# ===============================
# MOUNT SUBVOLUMES
# ===============================
mount_opts="noatime,ssd,discard=async,compress=zstd"
special_opts="nodatacow,compress=no"
root_dev="${DISK}2"

mount -o "$mount_opts,subvol=@" "$root_dev" /mnt

declare -A subvolumes=( 
    [@home]="/mnt/home" 
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
# CREATE SWAPFILE
# ===============================
swapfile="/mnt/.swap/swapfile"
btrfs filesystem mkswapfile --size "$SWAP_SIZE" $swapfile
swapon $swapfile

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
Server = https://mirror.pseudoform.org/\$repo/os/\$arch
Server = https://pkg.fef.moe/archlinux/\$repo/os/\$arch
Server = https://berlin.mirror.pkgbuild.com/\$repo/os/\$arch
Server = https://cdnmirror.com/archlinux/\$repo/os/\$arch
Server = https://mirror.ubrco.de/archlinux/\$repo/os/\$arch
MIRRORS
fi

# ===============================
# PACSTRAP
# ===============================
pacstrap -K /mnt base linux linux-firmware linux-headers snapper \
    btrfs-progs sudo vim nano networkmanager grub efibootmgr os-prober grub-btrfs inotify-tools

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

# Initramfs
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard consolefont modconf block btrfs filesystems)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Bootloader - GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# --- Snapper ---
snapper --no-dbus -c root create-config /
snapper --no-dbus -c root set-config TIMELINE_CREATE=no
snapper --no-dbus -c root set-config NUMBER_LIMIT=6
snapper --no-dbus -c root set-config NUMBER_LIMIT_IMPORTANT=2

# Enable NetworkManager
systemctl enable NetworkManager
#Enable Grub-BTRFS
systemctl enable grub-btrfsd
#Enable snapper-cleanup
systemctl enable snapper-cleanup.timer
EOF

# ===============================
# FINISH
# ===============================
swapoff "$swapfile" 2>/dev/null || true
umount -R /mnt
echo -e "\n✅ Installation complete!"
echo "1. Reboot the system"
echo "2. After login: sudo pacman -Syu"
