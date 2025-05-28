#!/bin/bash

# ASCII Art
echo -e "\033[1;36m"
cat << "EOF"
 ##   ##   ####    ######   #######            ####    ##   ##   #####   ######     ##     ####     ####
 ##   ##    ##      ##  ##   ##   #             ##     ###  ##  ##   ##  # ## #    ####     ##       ##
  ## ##     ##      ##  ##   ## #               ##     #### ##  #          ##     ##  ##    ##       ##
  ## ##     ##      #####    ####               ##     ## ####   #####     ##     ##  ##    ##       ##
   ###      ##      ##  ##   ## #               ##     ##  ###       ##    ##     ######    ##   #   ##   #
   ###      ##      ##  ##   ##   #             ##     ##   ##  ##   ##    ##     ##  ##    ##  ##   ##  ##
    #      ####    ######   #######            ####    ##   ##   #####    ####    ##  ##   #######  #######
EOF
echo -e "\033[0m"
echo -e "\033[1;35mVibe Install - Arch Linux Automated Installer\033[0m"
echo -e "\033[1;35mAuthor: NTFS DEV\033[0m"
echo ""

# Check for UEFI
if [ ! -d "/sys/firmware/efi/efivars" ]; then
    echo -e "\033[1;31mThis program supports only UEFI systems!\033[0m"
    exit 1
fi

# Check internet connection
echo -e "\033[1;34mChecking internet connection...\033[0m"
if ! ping -c 3 archlinux.org >/dev/null 2>&1; then
    echo -e "\033[1;31mNo internet connection detected!\033[0m"
    echo "Please connect to the internet before proceeding."
    exit 1
fi

# Bootloader selection
echo ""
echo -e "\033[1;32mSelect bootloader:\033[0m"
echo "1. GRUB (recommended for beginners)"
echo "2. rEFInd (alternative boot manager)"
read -p "Enter your choice (1 or 2): " bootloader_choice

# Disk selection
echo ""
echo -e "\033[1;34mAvailable disks:\033[0m"
lsblk -d -o NAME,SIZE,MODEL
echo ""
read -p "Enter the disk name (e.g., nvme0n1 or sda) for installation: " disk_name
disk="/dev/$disk_name"

# Wipe existing signatures
echo ""
echo -e "\033[1;31mWARNING: This will erase all data on $disk!\033[0m"
read -p "Do you want to proceed? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Installation aborted."
    exit 1
fi

echo -e "\033[1;34mWiping existing signatures on $disk...\033[0m"
wipefs -a $disk

# Partitioning
echo -e "\033[1;34mCreating partitions...\033[0m"
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
    echo        # Default last sector (rest of the disk)
    echo w      # Write changes
) | fdisk $disk

# Format partitions
echo -e "\033[1;34mFormatting partitions...\033[0m"
mkfs.fat -F32 ${disk}1
mkswap ${disk}2
swapon ${disk}2
mkfs.ext4 ${disk}3

# Mount partitions
echo -e "\033[1;34mMounting partitions...\033[0m"
mount ${disk}3 /mnt
mkdir /mnt/boot
mount ${disk}1 /mnt/boot

# Kernel selection
echo ""
echo -e "\033[1;32mSelect kernel:\033[0m"
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
echo -e "\033[1;34mInstalling base system...\033[0m"
pacstrap /mnt base $kernel linux-firmware

# Generate fstab
echo -e "\033[1;34mGenerating fstab...\033[0m"
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot setup
echo -e "\033[1;34mConfiguring the system...\033[0m"
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
    echo "vibe" > /etc/hostname
    echo "127.0.1.1 vibe.localdomain vibe" >> /etc/hosts
    
    # Install and configure bootloader
    if [ "$bootloader_choice" -eq 1 ]; then
        pacman -S --noconfirm grub efibootmgr
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        pacman -S --noconfirm refind
        refind-install
    fi
    
    # Install additional packages
    pacman -S --noconfirm sudo networkmanager nano
    
    # Create user
    useradd -m -G wheel -s /bin/bash vibeuser
    echo "Set password for vibeuser:"
    passwd vibeuser
    
    # Enable sudo for wheel group
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
    
    # Enable services
    systemctl enable NetworkManager
EOF

# Shell selection
echo ""
read -p "Do you want to install a shell? (y/n): " install_shell
if [ "$install_shell" = "y" ]; then
    echo -e "\033[1;32mSelect shell:\033[0m"
    echo "1. bash (default)"
    echo "2. zsh"
    echo "3. fish"
    read -p "Enter your choice (1-3): " shell_choice
    
    case $shell_choice in
        1) shell="bash";;
        2) shell="zsh";;
        3) shell="fish";;
        *) shell="bash";;
    esac
    
    arch-chroot /mnt /bin/bash <<EOF
        pacman -S --noconfirm $shell
        if [ "$shell" = "zsh" ]; then
            pacman -S --noconfirm zsh-completions
            chsh -s /bin/zsh vibeuser
        elif [ "$shell" = "fish" ]; then
            chsh -s /bin/fish vibeuser
        fi
EOF
fi

# Desktop environment selection
echo ""
read -p "Do you want to install a desktop environment? (y/n): " install_de
if [ "$install_de" = "y" ]; then
    echo -e "\033[1;32mSelect desktop environment:\033[0m"
    echo "1. GNOME"
    echo "2. KDE Plasma"
    echo "3. XFCE"
    echo "4. LXQt"
    read -p "Enter your choice (1-4): " de_choice
    
    arch-chroot /mnt /bin/bash <<EOF
        pacman -S --noconfirm xorg-server xorg-xinit
        case $de_choice in
            1)
                pacman -S --noconfirm gnome gnome-extra
                systemctl enable gdm
                ;;
            2)
                pacman -S --noconfirm plasma kde-applications
                systemctl enable sddm
                ;;
            3)
                pacman -S --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
                systemctl enable lightdm
                ;;
            4)
                pacman -S --noconfirm lxqt breeze-icons sddm
                systemctl enable sddm
                ;;
        esac
EOF
fi

# Cleanup and reboot
echo -e "\033[1;34mInstallation complete! Rebooting...\033[0m"
umount -R /mnt
reboot
