#!/bin/bash

# ASCII Art
clear
echo -e "\033[1;36m"
echo "##   ##   ####    ######   #######            ####    ##   ##   #####   ######     ##     ####     ####"
echo "##   ##    ##      ##  ##   ##   #             ##     ###  ##  ##   ##  # ## #    ####     ##       ##"
echo " ## ##     ##      ##  ##   ## #               ##     #### ##  #          ##     ##  ##    ##       ##"
echo " ## ##     ##      #####    ####               ##     ## ####   #####     ##     ##  ##    ##       ##"
echo "  ###      ##      ##  ##   ## #               ##     ##  ###       ##    ##     ######    ##   #   ##   #"
echo "  ###      ##      ##  ##   ##   #             ##     ##   ##  ##   ##    ##     ##  ##    ##  ##   ##  ##"
echo "   #      ####    ######   #######            ####    ##   ##   #####    ####    ##  ##   #######  #######"
echo -e "\033[0m"
echo -e "\033[1;35mArch Linux Automated Installer\033[0m"
echo -e "\033[1;33mAuthor: NTFS DEV\033[0m"
echo ""

# Check for UEFI
if [ ! -d "/sys/firmware/efi" ]; then
    echo -e "\033[1;31mThis program only supports UEFI systems.\033[0m"
    exit 1
fi

# Check internet connection
echo -e "\033[1;34mChecking internet connection...\033[0m"
if ! ping -c 3 archlinux.org >/dev/null 2>&1; then
    echo -e "\033[1;31mNo internet connection detected. Please connect to the internet before proceeding.\033[0m"
    exit 1
fi

# Get disk name
lsblk
echo ""
read -p "Enter the disk name to install Arch Linux on (e.g., nvme0n1, sda): " disk

# Partitioning
echo -e "\033[1;34mPartitioning disk...\033[0m"
(
echo g      # Create new GPT partition table
echo n      # Add new partition
echo 1      # Partition number 1
echo        # Default first sector
echo +550M  # Size 550MB
echo n      # Add new partition
echo 2      # Partition number 2
echo        # Default first sector
echo +2G    # Size 2GB
echo n      # Add new partition
echo 3      # Partition number 3
echo        # Default first sector
echo        # Default last sector (rest of the disk)
echo t      # Change partition type
echo 1      # Select partition 1
echo 1      # EFI System
echo t      # Change partition type
echo 2      # Select partition 2
echo 19     # Linux swap
echo w      # Write changes
) | fdisk /dev/$disk

# Format partitions
echo -e "\033[1;34mFormatting partitions...\033[0m"
mkfs.fat -F32 /dev/${disk}1
mkswap /dev/${disk}2
swapon /dev/${disk}2
mkfs.ext4 /dev/${disk}3

# Mount partitions
echo -e "\033[1;34mMounting partitions...\033[0m"
mount /dev/${disk}3 /mnt
mkdir /mnt/boot
mount /dev/${disk}1 /mnt/boot

# Select kernel
echo -e "\033[1;34mSelect kernel to install:\033[0m"
echo "1) linux (default)"
echo "2) linux-lts (long term support)"
echo "3) linux-zen (tuned for performance)"
read -p "Enter choice (1-3): " kernel_choice

case $kernel_choice in
    1) kernel="linux";;
    2) kernel="linux-lts";;
    3) kernel="linux-zen";;
    *) kernel="linux";;
esac

# Install base system
echo -e "\033[1;34mInstalling base system...\033[0m"
pacstrap /mnt base $kernel linux-firmware

# Generate fstab
echo -e "\033[1;34mGenerating fstab...\033[0m"
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot setup
echo -e "\033[1;34mConfiguring system...\033[0m"
arch-chroot /mnt /bin/bash <<EOF
# Set timezone
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "arch" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 arch.localdomain arch" >> /etc/hosts

# Install and configure bootloader
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install additional packages
pacman -S --noconfirm sudo networkmanager nano

# Enable services
systemctl enable NetworkManager

# Set root password
echo "Setting root password:"
passwd

# Create user
read -p "Do you want to create a new user? [y/n]: " create_user
if [ "$create_user" == "y" ]; then
    read -p "Enter username: " username
    useradd -m -G wheel $username
    echo "Setting password for $username:"
    passwd $username
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
fi

# Install desktop environment
read -p "Do you want to install a desktop environment? [y/n]: " install_de
if [ "$install_de" == "y" ]; then
    echo "1) GNOME"
    echo "2) KDE Plasma"
    echo "3) XFCE"
    echo "4) LXDE"
    read -p "Enter choice (1-4): " de_choice
    
    case \$de_choice in
        1) 
            pacman -S --noconfirm gnome gdm
            systemctl enable gdm
            ;;
        2) 
            pacman -S --noconfirm plasma sddm
            systemctl enable sddm
            ;;
        3) 
            pacman -S --noconfirm xfce4 lightdm lightdm-gtk-greeter
            systemctl enable lightdm
            ;;
        4) 
            pacman -S --noconfirm lxde lightdm lightdm-gtk-greeter
            systemctl enable lightdm
            ;;
    esac
fi
EOF

# Cleanup and reboot
echo -e "\033[1;32mInstallation complete!\033[0m"
umount -R /mnt
echo -e "\033[1;33mRebooting in 5 seconds...\033[0m"
sleep 5
reboot
