#!/bin/bash

# =============================================
# vibeinstall
# Author: NTFSDEV 
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

# --- Kernel selection ---
kernel_menu() {
    echo -e "${GREEN}Select kernel:${NC}"
    echo "1) Standard (linux)"
    echo "2) LTS (linux-lts)"
    echo "3) Zen (linux-zen)"
    echo -n "Your choice (1/2/3): "
    read kernel_choice

    case $kernel_choice in
        1) KERNEL="linux" ;;
        2) KERNEL="linux-lts" ;;
        3) KERNEL="linux-zen" ;;
        *) KERNEL="linux" ;;
    esac
}

# --- Network setup (Wi-Fi/Ethernet) ---
setup_network() {
    echo -e "${YELLOW}Configuring network...${NC}"

    # Ethernet (if available)
    if ip link show eth0 &>/dev/null; then
        echo -e "${GREEN}Ethernet detected, configuring...${NC}"
        dhcpcd eth0
    fi

    # Wi-Fi (using iwd)
    if ip link show wlan0 &>/dev/null; then
        echo -e "${GREEN}Wi-Fi detected, enter credentials:${NC}"
        echo -n "SSID: "
        read wifi_ssid
        echo -n "Password: "
        read -s wifi_pass
        echo

        # Configure using iwd
        iwctl station wlan0 scan
        iwctl station wlan0 connect "$wifi_ssid" --passphrase "$wifi_pass"
        dhcpcd wlan0
    fi

    # Internet check
    if ! ping -c 3 archlinux.org &>/dev/null; then
        echo -e "${RED}No internet connection! Check network settings.${NC}"
        exit 1
    fi
}

# --- Dual Boot selection ---
dual_boot_choice() {
    echo -n -e "${GREEN}Enable Dual Boot with Windows? (y/N): ${NC}"
    read dual_boot
    if [[ $dual_boot == [yY] ]]; then
        DUAL_BOOT=true
        echo -e "${YELLOW}Dual Boot mode activated${NC}"
    else
        DUAL_BOOT=false
        echo -e "${YELLOW}Only Arch Linux will be installed${NC}"
    fi
}

# --- Disk partitioning (auto/GPT) ---
auto_partition() {
    echo -e "${YELLOW}Select installation disk:${NC}"
    lsblk -d -o NAME,SIZE,MODEL
    echo -n "Disk name (e.g., sda/nvme0n1): "
    read DISK

    # Disk cleanup (GPT)
    echo -e "${RED}WARNING! All data on /dev/${DISK} will be erased!${NC}"
    read -p "Confirm (y/N): " confirm
    [[ $confirm != [yY] ]] && exit 1

    parted -s /dev/${DISK} mklabel gpt

    # Create partitions:
    # 1. EFI (500M)
    # 2. Swap (size = RAM)
    # 3. Root (remaining space)
    RAM_SIZE=$(free -m | awk '/Mem:/ {print $2}')
    parted -s /dev/${DISK} mkpart primary fat32 1MiB 501MiB
    parted -s /dev/${DISK} set 1 esp on
    parted -s /dev/${DISK} mkpart primary linux-swap 501MiB $(($RAM_SIZE + 501))MiB
    parted -s /dev/${DISK} mkpart primary ext4 $(($RAM_SIZE + 501))MiB 100%

    # Formatting
    mkfs.fat -F32 /dev/${DISK}1
    mkswap /dev/${DISK}2
    mkfs.ext4 /dev/${DISK}3

    # Mounting
    mount /dev/${DISK}3 /mnt
    mkdir -p /mnt/boot/efi
    mount /dev/${DISK}1 /mnt/boot/efi
    swapon /dev/${DISK}2
}

# --- System installation ---
install_arch() {
    echo -e "${YELLOW}Downloading and installing Arch Linux...${NC}"
    pacstrap /mnt base base-devel $KERNEL linux-firmware

    # Fstab
    genfstab -U /mnt >> /mnt/etc/fstab
}

# --- System configuration ---
configure_system() {
    # Timezone (Moscow)
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
    arch-chroot /mnt hwclock --systohc

    # Locales
    echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    echo "ru_RU.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

    # Hostname
    echo "vibearch" > /mnt/etc/hostname
    echo "127.0.0.1 localhost" >> /mnt/etc/hosts
    echo "::1 localhost" >> /mnt/etc/hosts
    echo "127.0.1.1 vibearch.localdomain vibearch" >> /mnt/etc/hosts

    # Root password
    echo -e "${GREEN}Set root password:${NC}"
    arch-chroot /mnt passwd
}

# --- Bootloader installation (GRUB) ---
install_grub() {
    echo -e "${YELLOW}Installing GRUB...${NC}"
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr os-prober
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

    # Dual Boot configuration if selected
    if $DUAL_BOOT; then
        echo -e "${GREEN}Configuring Dual Boot with Windows...${NC}"
        echo "GRUB_DISABLE_OS_PROBER=false" >> /mnt/etc/default/grub
    fi

    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

# --- User creation ---
create_user() {
    echo -n "Enter username: "
    read USERNAME
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"
    echo -e "${GREEN}Set password for $USERNAME:${NC}"
    arch-chroot /mnt passwd "$USERNAME"

    # Sudo
    echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
}

# --- Additional packages (network, audio) ---
install_extras() {
    arch-chroot /mnt pacman -S --noconfirm networkmanager sudo pipewire pulseaudio
    arch-chroot /mnt systemctl enable NetworkManager
}

# --- GUI (optional) ---
install_gui() {
    read -p "Install GUI? (y/N): " gui_choice
    if [[ $gui_choice == [yY] ]]; then
        echo -e "${GREEN}Installing GNOME...${NC}"
        arch-chroot /mnt pacman -S --noconfirm xorg gnome gnome-extra gdm
        arch-chroot /mnt systemctl enable gdm
    fi
}

# ===== MAIN =====
clear
echo -e "${GREEN}=== VibeArchInstall 2.1 (FULL AUTO) ===${NC}"

# 1. Kernel selection
kernel_menu

# 2. Network setup
setup_network

# 3. Dual Boot choice
dual_boot_choice

# 4. Disk partitioning
auto_partition

# 5. Arch installation
install_arch

# 6. System configuration
configure_system

# 7. GRUB (with Dual Boot option)
install_grub

# 8. User creation
create_user

# 9. Additional packages
install_extras

# 10. GUI (optional)
install_gui

# Done!
echo -e "${GREEN}Installation complete!${NC}"
echo -e "Reboot command: ${YELLOW}umount -R /mnt && reboot${NC}"
