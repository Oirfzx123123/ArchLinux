#!/bin/bash

# =============================================
# VibeInstall - Arch Linux Installer
# Created by NTFSDEV
# Inspired by Archinstall
# =============================================

# --- Colors and styles ---
BOLD=$(tput bold)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# --- ASCII Art ---
show_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo " ██▒   █▓ ▄▄▄       ██▓     ██▓    ▓█████ "
    echo "▓██░   █▒▒████▄    ▓██▒    ▓██▒    ▓█   ▀ "
    echo " ▓██  █▒░▒██  ▀█▄  ▒██░    ▒██░    ▒███   "
    echo "  ▒██ █░░░██▄▄▄▄██ ▒██░    ▒██░    ▒▓█  ▄ "
    echo "   ▒▀█░   ▓█   ▓██▒░██████▒░██████▒░▒████▒"
    echo "   ░ ▐░   ▒▒   ▓▒█░░ ▒░▓  ░░ ▒░▓  ░░░ ▒░ ░"
    echo "   ░ ░░    ▒   ▒▒ ░░ ░ ▒  ░░ ░ ▒  ░ ░ ░  ░"
    echo "     ░░    ░   ▒     ░ ░     ░ ░      ░   "
    echo "      ░        ░  ░    ░  ░    ░  ░   ░  ░"
    echo "     ░                                   "
    echo -e "${RESET}"
    echo -e "${BLUE}${BOLD}=== Arch Linux Installation ===${RESET}"
    echo
}

# --- Check root ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}${BOLD}ERROR: This script must be run as root!${RESET}"
        exit 1
    fi
}

# --- Check UEFI ---
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        echo -e "${RED}${BOLD}ERROR: System is not in UEFI mode!${RESET}"
        echo -e "${YELLOW}Please enable UEFI in BIOS and try again.${RESET}"
        exit 1
    fi
}

# --- Network setup ---
setup_network() {
    echo -e "${YELLOW}${BOLD}:: Network Configuration ::${RESET}"
    
    # Ethernet
    if ip link show eth0 &>/dev/null; then
        echo -e "${GREEN}» Ethernet detected, configuring...${RESET}"
        dhcpcd eth0
    fi

    # Wi-Fi
    if ip link show wlan0 &>/dev/null; then
        echo -e "${GREEN}» Wi-Fi detected${RESET}"
        read -p "${BLUE}? Enter SSID: ${RESET}" wifi_ssid
        read -sp "${BLUE}? Enter Password: ${RESET}" wifi_pass
        echo
        
        iwctl station wlan0 scan
        iwctl station wlan0 connect "$wifi_ssid" --passphrase "$wifi_pass"
        dhcpcd wlan0
    fi

    # Verify internet
    echo -e "${YELLOW}» Verifying internet connection...${RESET}"
    if ! ping -c 3 archlinux.org &>/dev/null; then
        echo -e "${RED}${BOLD}ERROR: No internet connection!${RESET}"
        exit 1
    fi
}

# --- Disk selection ---
select_disk() {
    echo -e "${YELLOW}${BOLD}:: Disk Selection ::${RESET}"
    echo -e "${BLUE}Available disks:${RESET}"
    lsblk -d -o NAME,SIZE,MODEL
    
    while true; do
        read -p "${BLUE}? Enter disk name (e.g., sda/nvme0n1): ${RESET}" DISK
        DISK="/dev/$DISK"
        
        if [[ -b "$DISK" ]]; then
            break
        else
            echo -e "${RED}» Disk $DISK not found!${RESET}"
        fi
    done
}

# --- Partitioning ---
partition_disk() {
    echo -e "${RED}${BOLD}:: WARNING ::${RESET}"
    echo -e "${RED}All data on $DISK will be erased!${RESET}"
    read -p "${BLUE}? Confirm (y/N): ${RESET}" confirm
    
    if [[ "$confirm" != [yY] ]]; then
        echo -e "${YELLOW}» Installation canceled${RESET}"
        exit 0
    fi

    echo -e "${YELLOW}» Partitioning disk...${RESET}"
    
    # Clear disk
    wipefs -af "$DISK"
    parted -s "$DISK" mklabel gpt
    
    # Create partitions
    RAM_SIZE=$(free -m | awk '/Mem:/ {print $2}')
    EFI_SIZE=513
    SWAP_SIZE=$((RAM_SIZE * 2))  # Double RAM for swap
    
    parted -s "$DISK" mkpart primary fat32 1MiB ${EFI_SIZE}MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary linux-swap ${EFI_SIZE}MiB $((EFI_SIZE + SWAP_SIZE))MiB
    parted -s "$DISK" mkpart primary ext4 $((EFI_SIZE + SWAP_SIZE))MiB 100%
    
    # Format partitions
    echo -e "${YELLOW}» Formatting partitions...${RESET}"
    mkfs.fat -F32 "${DISK}p1" || { echo -e "${RED}» Failed to format EFI partition!${RESET}"; exit 1; }
    mkswap "${DISK}p2" || { echo -e "${RED}» Failed to create swap!${RESET}"; exit 1; }
    mkfs.ext4 -F "${DISK}p3" || { echo -e "${RED}» Failed to format root partition!${RESET}"; exit 1; }
    
    # Mount partitions
    echo -e "${YELLOW}» Mounting partitions...${RESET}"
    mount "${DISK}p3" /mnt || { echo -e "${RED}» Failed to mount root partition!${RESET}"; exit 1; }
    mkdir -p /mnt/boot/efi || { echo -e "${RED}» Failed to create boot directory!${RESET}"; exit 1; }
    mount "${DISK}p1" /mnt/boot/efi || { echo -e "${RED}» Failed to mount EFI partition!${RESET}"; exit 1; }
    swapon "${DISK}p2" || { echo -e "${RED}» Failed to enable swap!${RESET}"; exit 1; }
}

# --- System installation ---
install_system() {
    echo -e "${YELLOW}${BOLD}:: System Installation ::${RESET}"
    
    # Kernel selection
    echo -e "${BLUE}? Select kernel:${RESET}"
    select KERNEL in "Standard (linux)" "LTS (linux-lts)" "Zen (linux-zen)"; do
        case $REPLY in
            1) KERNEL_PKGS="linux linux-headers"; break ;;
            2) KERNEL_PKGS="linux-lts linux-lts-headers"; break ;;
            3) KERNEL_PKGS="linux-zen linux-zen-headers"; break ;;
            *) echo -e "${RED}» Invalid option!${RESET}";;
        esac
    done
    
    # Install base system
    echo -e "${YELLOW}» Installing base system...${RESET}"
    pacstrap /mnt base base-devel $KERNEL_PKGS linux-firmware || { echo -e "${RED}» Installation failed!${RESET}"; exit 1; }
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab || { echo -e "${RED}» Failed to generate fstab!${RESET}"; exit 1; }
}

# --- System configuration ---
configure_system() {
    echo -e "${YELLOW}${BOLD}:: System Configuration ::${RESET}"
    
    # Hostname
    read -p "${BLUE}? Enter hostname [archlinux]: ${RESET}" hostname
    hostname=${hostname:-archlinux}
    echo "$hostname" > /mnt/etc/hostname
    
    # Timezone
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
    arch-chroot /mnt hwclock --systohc
    
    # Locale
    echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    echo "ru_RU.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    
    # Hosts
    cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOF
    
    # Root password
    echo -e "${YELLOW}» Set root password:${RESET}"
    arch-chroot /mnt passwd
}

# --- Bootloader installation ---
install_bootloader() {
    echo -e "${YELLOW}${BOLD}:: Bootloader Installation ::${RESET}"
    
    # Dual Boot question
    read -p "${BLUE}? Enable Dual Boot with Windows? [y/N]: ${RESET}" dual_boot
    
    # Install GRUB
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr os-prober
    
    if [[ "$dual_boot" == [yY] ]]; then
        echo -e "${GREEN}» Configuring Dual Boot...${RESET}"
        echo "GRUB_DISABLE_OS_PROBER=false" >> /mnt/etc/default/grub
    fi
    
    # Install GRUB
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

# --- User creation ---
create_user() {
    echo -e "${YELLOW}${BOLD}:: User Creation ::${RESET}"
    
    read -p "${BLUE}? Enter username: ${RESET}" username
    
    # Create user
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"
    
    # Set password
    echo -e "${YELLOW}» Set password for $username:${RESET}"
    arch-chroot /mnt passwd "$username"
    
    # Sudo permissions
    echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
}

# --- Install additional packages ---
install_extras() {
    echo -e "${YELLOW}${BOLD}:: Additional Packages ::${RESET}"
    
    # Base utilities
    arch-chroot /mnt pacman -S --noconfirm \
        networkmanager \
        sudo \
        nano \
        git \
        reflector
    
    # Enable NetworkManager
    arch-chroot /mnt systemctl enable NetworkManager
}

# --- Main function ---
main() {
    show_header
    check_root
    check_uefi
    setup_network
    select_disk
    partition_disk
    install_system
    configure_system
    install_bootloader
    create_user
    install_extras
    
    # Completion
    echo -e "${GREEN}${BOLD}» Installation complete!${RESET}"
    echo -e "${BLUE}» You can now reboot with: ${YELLOW}umount -R /mnt && reboot${RESET}"
}

# Start installation
main
