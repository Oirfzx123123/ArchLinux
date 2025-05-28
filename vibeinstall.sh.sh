#!/bin/bash

# =============================================
# videinstall
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

# --- Enhanced UEFI check ---
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        echo -e "${RED}Error: System is not in UEFI mode!${NC}"
        echo -e "${YELLOW}Please enable UEFI in BIOS and try again.${NC}"
        exit 1
    fi
}

# --- Network setup with validation ---
setup_network() {
    echo -e "${YELLOW}Configuring network...${NC}"
    
    # Ethernet
    if ip link show eth0 &>/dev/null; then
        echo -e "${GREEN}Ethernet detected, configuring...${NC}"
        if ! dhcpcd eth0; then
            echo -e "${RED}Failed to configure Ethernet!${NC}"
            exit 1
        fi
    fi

    # Wi-Fi
    if ip link show wlan0 &>/dev/null; then
        echo -e "${GREEN}Wi-Fi detected, enter credentials:${NC}"
        read -p "SSID: " wifi_ssid
        read -sp "Password: " wifi_pass
        echo
        
        if ! iwctl station wlan0 scan; then
            echo -e "${RED}Failed to scan for networks!${NC}"
            exit 1
        fi
        
        if ! iwctl station wlan0 connect "$wifi_ssid" --passphrase "$wifi_pass"; then
            echo -e "${RED}Failed to connect to Wi-Fi!${NC}"
            exit 1
        fi
        
        if ! dhcpcd wlan0; then
            echo -e "${RED}Failed to get IP address!${NC}"
            exit 1
        fi
    fi

    # Verify internet with timeout
    echo -e "${YELLOW}Verifying internet connection...${NC}"
    if ! ping -c 3 -W 5 archlinux.org &>/dev/null; then
        echo -e "${RED}No internet connection! Check network settings.${NC}"
        exit 1
    fi
}

# --- Disk partitioning with validation ---
prepare_disk() {
    echo -e "${YELLOW}Preparing disk...${NC}"
    
    # Show available disks
    echo -e "${GREEN}Available disks:${NC}"
    lsblk -d -o NAME,SIZE,MODEL
    
    # Select disk
    read -p "Enter disk name (e.g., sda/nvme0n1): " DISK
    DISK="/dev/${DISK}"
    
    # Verify disk exists
    if [[ ! -b $DISK ]]; then
        echo -e "${RED}Error: Disk $DISK does not exist!${NC}"
        exit 1
    fi
    
    # Confirm destruction
    echo -e "${RED}WARNING: All data on $DISK will be erased!${NC}"
    read -p "Confirm (y/N): " confirm
    [[ $confirm != [yY] ]] && exit 1
    
    # Clean disk
    echo -e "${YELLOW}Cleaning disk...${NC}"
    wipefs -af $DISK
    parted -s $DISK mklabel gpt
    
    # Calculate sizes
    RAM_SIZE=$(free -m | awk '/Mem:/ {print $2}')
    SWAP_SIZE=$((RAM_SIZE * 2)) # Double RAM for swap
    EFI_SIZE=513 # 513MiB for EFI
    ROOT_START=$((EFI_SIZE + SWAP_SIZE))
    
    # Create partitions
    echo -e "${YELLOW}Creating partitions...${NC}"
    parted -s $DISK mkpart primary fat32 1MiB ${EFI_SIZE}MiB
    parted -s $DISK set 1 esp on
    parted -s $DISK mkpart primary linux-swap ${EFI_SIZE}MiB ${ROOT_START}MiB
    parted -s $DISK mkpart primary ext4 ${ROOT_START}MiB 100%
    
    # Format partitions
    echo -e "${YELLOW}Formatting partitions...${NC}"
    mkfs.fat -F32 ${DISK}p1 || { echo -e "${RED}Failed to format EFI partition!${NC}"; exit 1; }
    mkswap ${DISK}p2 || { echo -e "${RED}Failed to create swap!${NC}"; exit 1; }
    mkfs.ext4 -F ${DISK}p3 || { echo -e "${RED}Failed to format root partition!${NC}"; exit 1; }
    
    # Mount partitions
    echo -e "${YELLOW}Mounting partitions...${NC}"
    mount ${DISK}p3 /mnt || { echo -e "${RED}Failed to mount root partition!${NC}"; exit 1; }
    mkdir -p /mnt/boot/efi || { echo -e "${RED}Failed to create boot directory!${NC}"; exit 1; }
    mount ${DISK}p1 /mnt/boot/efi || { echo -e "${RED}Failed to mount EFI partition!${NC}"; exit 1; }
    swapon ${DISK}p2 || { echo -e "${RED}Failed to enable swap!${NC}"; exit 1; }
    
    # Verify mounts
    if ! mountpoint -q /mnt || ! mountpoint -q /mnt/boot/efi; then
        echo -e "${RED}Mounting failed!${NC}"
        exit 1
    fi
}

# --- Package installation with validation ---
install_packages() {
    echo -e "${YELLOW}Installing base system...${NC}"
    
    # Select kernel
    PS3="Select kernel: "
    select KERNEL in "linux" "linux-lts" "linux-zen"; do
        case $KERNEL in
            linux) KERNEL_PKGS="linux linux-headers"; break ;;
            linux-lts) KERNEL_PKGS="linux-lts linux-lts-headers"; break ;;
            linux-zen) KERNEL_PKGS="linux-zen linux-zen-headers"; break ;;
            *) echo "Invalid option";;
        esac
    done
    
    # Install base system
    if ! pacstrap /mnt base base-devel $KERNEL_PKGS linux-firmware; then
        echo -e "${RED}Failed to install base system!${NC}"
        exit 1
    fi
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab || { echo -e "${RED}Failed to generate fstab!${NC}"; exit 1; }
}

# --- System configuration ---
configure_system() {
    echo -e "${YELLOW}Configuring system...${NC}"
    
    # Basic configuration
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
    arch-chroot /mnt hwclock --systohc
    
    # Locales
    echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    echo "ru_RU.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    
    # Hostname
    echo "archlinux" > /mnt/etc/hostname
    cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlinux.localdomain archlinux
EOF
    
    # Root password
    echo -e "${GREEN}Set root password:${NC}"
    arch-chroot /mnt passwd
}

# --- Bootloader installation ---
install_bootloader() {
    echo -e "${YELLOW}Installing bootloader...${NC}"
    
    # Install GRUB
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr os-prober
    
    # Install to EFI
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
    
    # Configure GRUB
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    
    # Verify installation
    if [[ ! -f /mnt/boot/efi/EFI/GRUB/grubx64.efi ]]; then
        echo -e "${RED}GRUB installation failed!${NC}"
        exit 1
    fi
}

# --- User creation ---
create_user() {
    echo -e "${YELLOW}Creating user...${NC}"
    
    read -p "Enter username: " username
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"
    
    echo -e "${GREEN}Set password for $username:${NC}"
    arch-chroot /mnt passwd "$username"
    
    # Sudo permissions
    echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
}

# --- Main installation flow ---
main() {
    clear
    echo -e "${GREEN}=== Robust Arch Linux Installer ===${NC}"
    
    # Initial checks
    check_uefi
    setup_network
    
    # Disk preparation
    prepare_disk
    
    # Installation
    install_packages
    configure_system
    install_bootloader
    create_user
    
    # Cleanup
    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "You can now reboot with: ${YELLOW}umount -R /mnt && reboot${NC}"
}

# Execute main function
main
