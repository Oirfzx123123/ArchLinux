#!/bin/bash

# ASCII Art
clear
echo -e "\e[1;36m"
echo "##   ##   ####    ######   #######            ####    ##   ##   #####   ######     ##     ####     ####"
echo "##   ##    ##      ##  ##   ##   #             ##     ###  ##  ##   ##  # ## #    ####     ##       ##"
echo " ## ##     ##      ##  ##   ## #               ##     #### ##  #          ##     ##  ##    ##       ##"
echo " ## ##     ##      #####    ####               ##     ## ####   #####     ##     ##  ##    ##       ##"
echo "  ###      ##      ##  ##   ## #               ##     ##  ###       ##    ##     ######    ##   #   ##   #"
echo "  ###      ##      ##  ##   ##   #             ##     ##   ##  ##   ##    ##     ##  ##    ##  ##   ##  ##"
echo "   #      ####    ######   #######            ####    ##   ##   #####    ####    ##  ##   #######  #######"
echo -e "\e[0m"
echo -e "\e[1;33mArch Linux Automated Installer - Vibe Install\e[0m"
echo -e "\e[1;33mAuthor: NTFS DEV\e[0m"
echo ""

# Check for UEFI
if [ ! -d "/sys/firmware/efi/efivars" ]; then
    echo -e "\e[1;31mThis program only supports UEFI mode.\e[0m"
    exit 1
fi

# Check internet connection
ping -c 1 archlinux.org > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "\e[1;31mNo internet connection detected. Please connect to the internet before proceeding.\e[0m"
    exit 1
fi

# Bootloader selection
echo -e "\e[1;34mSelect bootloader:\e[0m"
echo "1. GRUB (recommended for beginners)"
echo "2. rEFInd (alternative boot manager)"
read -p "Enter your choice (1 or 2): " bootloader_choice

# Disk selection
lsblk
read -p "Enter the disk to install Arch Linux on (e.g., sda, nvme0n1): " disk_name
disk="/dev/$disk_name"

# Wipe existing signatures
echo -e "\e[1;33mWiping existing disk signatures...\e[0m"
wipefs -a $disk

# Partitioning
echo -e "\e[1;33mPartitioning the disk...\e[0m"
(
echo g      # Create new GPT partition table
echo n      # Add new partition
echo 1      # Partition number 1
echo        # Default first sector
echo +550M  # Size 550MB for EFI
echo t      # Change partition type
echo 1      # EFI System
echo n      # Add new partition
echo 2      # Partition number 2
echo        # Default first sector
echo +2G    # Size 2GB for swap
echo t      # Change partition type
echo 2      # Select partition 2
echo 19     # Linux swap
echo n      # Add new partition
echo 3      # Partition number 3
echo        # Default first sector
echo        # Use remaining space for root
echo w      # Write changes
) | fdisk $disk

# Format partitions
echo -e "\e[1;33mFormatting partitions...\e[0m"
mkfs.fat -F32 ${disk}1
mkswap ${disk}2
swapon ${disk}2
mkfs.ext4 ${disk}3

# Mount partitions
echo -e "\e[1;33mMounting partitions...\e[0m"
mount ${disk}3 /mnt
mkdir -p /mnt/boot/efi
mount ${disk}1 /mnt/boot/efi

# Kernel selection
echo -e "\e[1;34mSelect kernel:\e[0m"
echo "1. linux (standard)"
echo "2. linux-lts (long term support)"
echo "3. linux-zen (tuned for performance)"
read -p "Enter your choice (1-3): " kernel_choice

case $kernel_choice in
    1) kernel="linux";;
    2) kernel="linux-lts";;
    3) kernel="linux-zen";;
    *) kernel="linux";;
esac

# Install base system
echo -e "\e[1;33mInstalling base system...\e[0m"
pacstrap /mnt base $kernel linux-firmware

# Generate fstab
echo -e "\e[1;33mGenerating fstab...\e[0m"
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo -e "\e[1;33mConfiguring the new system...\e[0m"
arch-chroot /mnt /bin/bash <<EOF
# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "arch" > /etc/hostname
echo -e "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\tarch.localdomain\tarch" > /etc/hosts

# Install additional packages
pacman -Sy --noconfirm vim nano networkmanager $kernel-headers

# Install bootloader
if [ "$bootloader_choice" -eq 1 ]; then
    pacman -Sy --noconfirm grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
else
    pacman -Sy --noconfirm refind
    refind-install
fi

# Enable NetworkManager
systemctl enable NetworkManager

# Root password
echo "Set root password:"
passwd

# User creation
read -p "Do you want to create a new user? [y/n]: " create_user
if [ "$create_user" = "y" ]; then
    read -p "Enter username: " username
    useradd -m -G wheel -s /bin/bash $username
    echo "Set password for $username:"
    passwd $username
    # Allow wheel group to use sudo
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
fi

# Install desktop environment
read -p "Do you want to install a desktop environment? [y/n]: " install_de
if [ "$install_de" = "y" ]; then
    echo "Available desktop environments:"
    echo "1. GNOME"
    echo "2. KDE Plasma"
    echo "3. Xfce"
    echo "4. LXQt"
    read -p "Enter your choice (1-4): " de_choice
    
    case $de_choice in
        1) pacman -Sy --noconfirm gnome gnome-extra gdm
           systemctl enable gdm;;
        2) pacman -Sy --noconfirm plasma kde-applications sddm
           systemctl enable sddm;;
        3) pacman -Sy --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
           systemctl enable lightdm;;
        4) pacman -Sy --noconfirm lxqt oxygen-icons sddm
           systemctl enable sddm;;
    esac
fi
EOF

# Cleanup and reboot
echo -e "\e[1;32mInstallation complete! Rebooting in 10 seconds...\e[0m"
sleep 10
umount -R /mnt
reboot
