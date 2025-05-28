#!/bin/bash

# =============================================
# vibeinstall
# NTFSDEV
# =============================================

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Check for root ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root!${NC}"
    exit 1
fi

# --- Check UEFI mode ---
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        echo -e "${RED}Error: System is not in UEFI mode!${NC}"
        echo -e "${YELLOW}Please enable UEFI in BIOS and try again.${NC}"
        exit 1
    fi
}

# --- Kernel selection ---
kernel_menu() {
    echo -e "${GREEN}Select kernel:${NC}"
    echo "1) Standard (linux)"
    echo "2) LTS (linux-lts)"
    echo "3) Zen (linux-zen)"
    echo -n "Your choice (1/2/3): "
    read kernel_choice

    case $kernel_choice in
        1) KERNEL="linux linux-headers" ;;
        2) KERNEL="linux-lts linux-lts-headers" ;;
        3) KERNEL="linux-zen linux-zen-headers" ;;
        *) KERNEL="linux linux-headers" ;;
    esac
}

# --- Network setup ---
setup_network() {
    echo -e "${YELLOW}Configuring network...${NC}"

    # Ethernet
    if ip link show eth0 &>/dev/null; then
        echo -e "${GREEN}Ethernet detected, configuring...${NC}"
        dhcpcd eth0
    fi

    # Wi-Fi
    if ip link show wlan0 &>/dev/null; then
        echo -e "${GREEN}Wi-Fi detected, enter credentials:${NC}"
        echo -n "SSID: "
        read wifi_ssid
        echo -n "Password: "
        read -s wifi_pass
        echo

        iwctl station wlan0 scan
        iwctl station wlan0 connect "$wifi_ssid" --passphrase "$wifi_pass"
        dhcpcd wlan0
    fi

    # Verify internet
    if ! ping -c 3 archlinux.org &>/dev/null; then
        echo -e "${RED}No internet connection! Check network settings.${NC}"
        exit 1
    fi
}

# --- Disk selection ---
select_disk() {
    echo -e "${YELLOW}Available disks:${NC}"
    lsblk -d -o NAME,SIZE,MODEL
    echo -n "Enter disk name (e.g., sda/nvme0n1): "
    read DISK
}

# --- Partitioning ---
partition_disk() {
    echo -e "${RED}WARNING: All data on /dev/${DISK} will be erased!${NC}"
    read -p "Confirm (y/N): " confirm
    [[ $confirm != [yY] ]] && exit 1

    # Clear disk
    wipefs -a /dev/$DISK
    parted -s /dev/$DISK mklabel gpt

    # Create partitions
    RAM_SIZE=$(free -m | awk '/Mem:/ {print $2}')
    parted -s /dev/$DISK mkpart primary fat32 1MiB 513MiB
    parted -s /dev/$DISK set 1 esp on
    parted -s /dev/$DISK mkpart primary linux-swap 513MiB $((513 + RAM_SIZE))MiB
    parted -s /dev/$DISK mkpart primary ext4 $((513 + RAM_SIZE))MiB 100%

    # Format partitions
    mkfs.fat -F32 /dev/${DISK}p1
    mkswap /dev/${DISK}p2
    mkfs.ext4 -F /dev/${DISK}p3

    # Mount partitions
    mount /dev/${DISK}p3 /mnt
    mkdir -p /mnt/boot/efi
    mount /dev/${DISK}p1 /mnt/boot/efi
    swapon /dev/${DISK}p2
}

# --- Install base system ---
install_base() {
    echo -e "${YELLOW}Installing Arch Linux...${NC}"
    pacstrap /mnt base base-devel $KERNEL linux-firmware
    genfstab -U /mnt >> /mnt/etc/fstab
}

# --- System configuration ---
configure_system() {
    # Timezone
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
    arch-chroot /mnt hwclock --systohc

    # Locale
    echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    echo "ru_RU.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

    # Hostname
    echo "archlinux" > /mnt/etc/hostname
    echo "127.0.0.1 localhost" >> /mnt/etc/hosts
    echo "::1 localhost" >> /mnt/etc/hosts
    echo "127.0.1.1 archlinux.localdomain archlinux" >> /mnt/etc/hosts

    # Root password
    echo -e "${GREEN}Set root password:${NC}"
    arch-chroot /mnt passwd
}

# --- Install bootloader ---
install_bootloader() {
    echo -e "${YELLOW}Installing GRUB bootloader...${NC}"
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr os-prober
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck

    # Configure Dual Boot if needed
    if [[ $DUAL_BOOT == true ]]; then
        echo -e "${GREEN}Configuring Dual Boot...${NC}"
        echo "GRUB_DISABLE_OS_PROBER=false" >> /mnt/etc/default/grub
    fi

    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

    # Verify EFI entry
    if ! arch-chroot /mnt efibootmgr | grep -q GRUB; then
        echo -e "${YELLOW}Creating manual EFI entry...${NC}"
        arch-chroot /mnt efibootmgr --create --disk /dev/$DISK --part 1 --loader /EFI/GRUB/grubx64.efi --label "Arch Linux" --unicode
    fi
}

# --- User setup ---
setup_user() {
    echo -n "Enter username: "
    read USERNAME
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"
    echo -e "${GREEN}Set password for $USERNAME:${NC}"
    arch-chroot /mnt passwd "$USERNAME"

    # Sudo permissions
    echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
}

# --- Install additional packages ---
install_essentials() {
    arch-chroot /mnt pacman -S --noconfirm \
        networkmanager \
        sudo \
        nano \
        git \
        reflector
    arch-chroot /mnt systemctl enable NetworkManager
}

# --- Install desktop environment ---
install_desktop() {
    read -p "Install GNOME desktop? (y/N): " choice
    if [[ $choice == [yY] ]]; then
        arch-chroot /mnt pacman -S --noconfirm \
            xorg \
            gnome \
            gnome-extra \
            gdm
        arch-chroot /mnt systemctl enable gdm
    fi
}

# --- Main installation ---
clear
echo -e "${GREEN}=== Arch Linux Installer ===${NC}"

# Verify UEFI
check_uefi

# Network setup
setup_network

# Dual Boot choice
read -p "Enable Dual Boot with Windows? (y/N): " dual_boot
if [[ $dual_boot == [yY] ]]; then
    DUAL_BOOT=true
    echo -e "${YELLOW}Dual Boot enabled${NC}"
else
    DUAL_BOOT=false
    echo -e "${YELLOW}Single boot (Arch only)${NC}"
fi

# Kernel selection
kernel_menu

# Disk setup
select_disk
partition_disk

# Installation
install_base
configure_system
install_bootloader
setup_user
install_essentials
install_desktop

# Completion
echo -e "${GREEN}Installation complete!${NC}"
echo -e "Unmount and reboot with: ${YELLOW}umount -R /mnt && reboot${NC}"
