#!/bin/bash

# ASCII Art
echo "##   ##   ####    ######   #######            ####    ##   ##   #####   ######     ##     ####     ####"
echo "##   ##    ##      ##  ##   ##   #             ##     ###  ##  ##   ##  # ## #    ####     ##       ##"
echo " ## ##     ##      ##  ##   ## #               ##     #### ##  #          ##     ##  ##    ##       ##"
echo " ## ##     ##      #####    ####               ##     ## ####   #####     ##     ##  ##    ##       ##"
echo "  ###      ##      ##  ##   ## #               ##     ##  ###       ##    ##     ######    ##   #   ##   #"
echo "  ###      ##      ##  ##   ##   #             ##     ##   ##  ##   ##    ##     ##  ##    ##  ##   ##  ##"
echo "   #      ####    ######   #######            ####    ##   ##   #####    ####    ##  ##   #######  #######"
echo ""
echo "Welcome to Vibe Install - Arch Linux Automated Installer"
echo "Created by [NTFS DEV]"
echo ""

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root!"
    exit 1
fi

# Check internet connection
echo "Checking internet connection..."
if ! ping -c 3 archlinux.org >/dev/null 2>&1; then
    echo "No internet connection detected. Please connect to the internet before proceeding."
    exit 1
fi
echo "Internet connection detected. Proceeding..."

# Disk selection
lsblk
echo ""
read -p "Enter the disk to install Arch Linux on (e.g., sda, nvme0n1): " disk
disk="/dev/$disk"

# Partitioning
echo ""
echo "Partitioning $disk..."
(
echo g      # Create new GPT partition table
echo n      # Add new partition
echo 1      # Partition number 1
echo        # Default first sector
echo +550M  # Partition size
echo n      # Add new partition
echo 2      # Partition number 2
echo        # Default first sector
echo +2G    # Partition size (swap)
echo n      # Add new partition
echo 3      # Partition number 3
echo        # Default first sector
echo        # Default last sector (rest of disk)
echo t      # Change partition type
echo 1      # Select partition 1
echo 1      # EFI System
echo t      # Change partition type
echo 2      # Select partition 2
echo 19     # Linux swap
echo w      # Write changes
) | fdisk $disk

# Format partitions
echo ""
echo "Formatting partitions..."
mkfs.fat -F32 ${disk}1
mkswap ${disk}2
swapon ${disk}2
mkfs.ext4 ${disk}3

# Mount filesystems
echo ""
echo "Mounting filesystems..."
mount ${disk}3 /mnt
mkdir /mnt/boot
mount ${disk}1 /mnt/boot

# Kernel selection
echo ""
echo "Select kernel to install:"
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
echo ""
echo "Installing base system with $kernel kernel..."
pacstrap /mnt base $kernel linux-firmware

# Generate fstab
echo ""
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot setup
echo ""
echo "Setting up chroot environment..."

# Create chroot script
cat <<EOF > /mnt/chroot.sh
#!/bin/bash

# Timezone
echo ""
echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

# Localization
echo ""
echo "Generating locales..."
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo ""
echo "Configuring network..."
echo "vibe-arch" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   vibe-arch.localdomain   vibe-arch
HOSTS

# Install additional packages
echo ""
echo "Installing additional packages..."
pacman -Syu --noconfirm grub efibootmgr networkmanager sudo nano

# Configure GRUB
echo ""
echo "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
echo ""
echo "Enabling services..."
systemctl enable NetworkManager

# User setup
echo ""
read -p "Enter username for new user: " username
useradd -m -G wheel -s /bin/bash \$username
echo "Set password for \$username:"
passwd \$username

# Sudo setup
echo ""
echo "Configuring sudo..."
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Set root password
echo ""
echo "Set root password:"
passwd

# Cleanup
rm /chroot.sh
EOF

# Make chroot script executable
chmod +x /mnt/chroot.sh

# Execute chroot script
arch-chroot /mnt /chroot.sh

# Cleanup
echo ""
echo "Cleaning up..."
umount -R /mnt
swapoff ${disk}2

echo ""
echo "Installation complete!"
echo "You can now reboot into your new Arch Linux system."
echo "Don't forget to remove the installation media!"
