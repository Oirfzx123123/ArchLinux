#!/bin/bash

# =============================================
# VibeInstall - Arch Linux Installer
# Fixed Disk Partitioning Version
# Created by NTFSDEV
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
    lsblk -d -o NAME,SIZE,MODEL | grep -v 'loop' | grep -v 'sr[0-9]'
    
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
    local DISK=$1
    
    echo -e "${RED}${BOLD}:: WARNING ::${RESET}"
    echo -e "${RED}All data on $DISK will be erased!${RESET}"
    read -p "${BLUE}? Confirm (type 'YES' to continue): ${RESET}" confirm
    
    if [[ "$confirm" != "YES" ]]; then
        echo -e "${YELLOW}» Installation canceled${RESET}"
        exit 0
    fi

    echo -e "${YELLOW}» Partitioning disk with fdisk...${RESET}"
    
    # Очистка диска
    echo -e "${GREEN}[1/7] Cleaning disk...${NC}"
    wipefs -a -f $DISK
    
    
    echo -e "${GREEN}[2/7] Creating partitions with fdisk...${NC}"
    echo -e "g\nn\n\n\n+550M\nn\n\n\n+2G\nn\n\n\n\nt\n1\n1\nt\n2\n19\nw\n" | fdisk $DISK
    
    
    if [[ $DISK == *"nvme"* ]]; then
        EFI_PART="${DISK}p1"
        SWAP_PART="${DISK}p2"
        ROOT_PART="${DISK}p3"
    else
        EFI_PART="${DISK}1"
        SWAP_PART="${DISK}2"
        ROOT_PART="${DISK}3"
    fi
    
    # Форматирование разделов
    echo -e "${GREEN}[3/7] Formatting EFI partition...${NC}"
    mkfs.fat -F32 $EFI_PART || {
        echo -e "${RED}ERROR: Failed to format EFI partition!${NC}"
        exit 1
    }
    
    echo -e "${GREEN}[4/7] Setting up swap...${NC}"
    mkswap $SWAP_PART || {
        echo -e "${RED}ERROR: Failed to create swap!${NC}"
        exit 1
    }
    
    echo -e "${GREEN}[5/7] Formatting root partition...${NC}"
    mkfs.ext4 -F $ROOT_PART || {
        echo -e "${RED}ERROR: Failed to format root partition!${NC}"
        exit 1
    }
    
    
    echo -e "${GREEN}[6/7] Mounting partitions...${NC}"
    mount $ROOT_PART /mnt || {
        echo -e "${RED}ERROR: Failed to mount root partition!${NC}"
        exit 1
    }
    
    mkdir -p /mnt/boot/efi || {
        echo -e "${RED}ERROR: Failed to create boot directory!${NC}"
        exit 1
    }
    
    mount $EFI_PART /mnt/boot/efi || {
        echo -e "${RED}ERROR: Failed to mount EFI partition!${NC}"
        exit 1
    }
    
    echo -e "${GREEN}[7/7] Activating swap...${NC}"
    swapon $SWAP_PART || {
        echo -e "${YELLOW}WARNING: Failed to enable swap! Continuing...${NC}"
    }
    
    echo -e "${GREEN}» Disk partitioned successfully!${RESET}"
    echo -e "Partition layout:"
    lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT $DISK
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
    if ! pacstrap /mnt base base-devel $KERNEL_PKGS linux-firmware; then
        echo -e "${RED}» Installation failed!${RESET}"
        exit 1
    fi
    
    # Generate fstab
    if ! genfstab -U /mnt >> /mnt/etc/fstab; then
        echo -e "${RED}» Failed to generate fstab!${RESET}"
        exit 1
    fi
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
    
    # Verify installation
    if [[ ! -f /mnt/boot/efi/EFI/GRUB/grubx64.efi ]]; then
        echo -e "${RED}» GRUB installation failed!${RESET}"
        exit 1
    fi
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
    partition_disk "$DISK"
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
