#!/bin/bash

# =============================================
# vibeinstall
# Автор: NTFSDEV 
# =============================================

# --- Цвета для красоты ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Проверка на root ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ошибка: Скрипт должен запускаться от root!${NC}"
    exit 1
fi

# --- Выбор ядра ---
kernel_menu() {
    echo -e "${GREEN}Выбери ядро:${NC}"
    echo "1) Стандартное (linux)"
    echo "2) LTS (linux-lts)"
    echo "3) Zen (linux-zen)"
    echo -n "Твой выбор (1/2/3): "
    read kernel_choice

    case $kernel_choice in
        1) KERNEL="linux" ;;
        2) KERNEL="linux-lts" ;;
        3) KERNEL="linux-zen" ;;
        *) KERNEL="linux" ;;
    esac
}

# --- Настройка сети (Wi-Fi/Ethernet) ---
setup_network() {
    echo -e "${YELLOW}Настраиваю сеть...${NC}"

    # Ethernet (если есть)
    if ip link show eth0 &>/dev/null; then
        echo -e "${GREEN}Найден Ethernet, настраиваю...${NC}"
        dhcpcd eth0
    fi

    # Wi-Fi (через iwd)
    if ip link show wlan0 &>/dev/null; then
        echo -e "${GREEN}Найден Wi-Fi, введи данные:${NC}"
        echo -n "SSID сети: "
        read wifi_ssid
        echo -n "Пароль: "
        read -s wifi_pass
        echo

        # Настройка через iwd
        iwctl station wlan0 scan
        iwctl station wlan0 connect "$wifi_ssid" --passphrase "$wifi_pass"
        dhcpcd wlan0
    fi

    # Проверка интернета
    if ! ping -c 3 archlinux.org &>/dev/null; then
        echo -e "${RED}Нет интернета! Проверь настройки сети.${NC}"
        exit 1
    fi
}

# --- Разметка диска (авто/GPT) ---
auto_partition() {
    echo -e "${YELLOW}Выбери диск для установки:${NC}"
    lsblk -d -o NAME,SIZE,MODEL
    echo -n "Имя диска (например, sda/nvme0n1): "
    read DISK

    # Очистка диска (GPT)
    echo -e "${RED}ВНИМАНИЕ! Весь диск /dev/${DISK} будет очищен!${NC}"
    read -p "Подтверди (y/N): " confirm
    [[ $confirm != [yY] ]] && exit 1

    parted -s /dev/${DISK} mklabel gpt

    # Создание разделов:
    # 1. EFI (500M)
    # 2. Swap (размер = RAM)
    # 3. Root (всё остальное)
    RAM_SIZE=$(free -m | awk '/Mem:/ {print $2}')
    parted -s /dev/${DISK} mkpart primary fat32 1MiB 501MiB
    parted -s /dev/${DISK} set 1 esp on
    parted -s /dev/${DISK} mkpart primary linux-swap 501MiB $(($RAM_SIZE + 501))MiB
    parted -s /dev/${DISK} mkpart primary ext4 $(($RAM_SIZE + 501))MiB 100%

    # Форматирование
    mkfs.fat -F32 /dev/${DISK}1
    mkswap /dev/${DISK}2
    mkfs.ext4 /dev/${DISK}3

    # Монтирование
    mount /dev/${DISK}3 /mnt
    mkdir -p /mnt/boot/efi
    mount /dev/${DISK}1 /mnt/boot/efi
    swapon /dev/${DISK}2
}

# --- Установка системы ---
install_arch() {
    echo -e "${YELLOW}Качаю и ставлю Arch Linux...${NC}"
    pacstrap /mnt base base-devel $KERNEL linux-firmware

    # Fstab
    genfstab -U /mnt >> /mnt/etc/fstab
}

# --- Настройка системы ---
configure_system() {
    # Часовой пояс (Москва)
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
    arch-chroot /mnt hwclock --systohc

    # Локали
    echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    echo "ru_RU.UTF-8 UTF-8" >> /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

    # Имя ПК
    echo "vibearch" > /mnt/etc/hostname
    echo "127.0.0.1 localhost" >> /mnt/etc/hosts
    echo "::1 localhost" >> /mnt/etc/hosts
    echo "127.0.1.1 vibearch.localdomain vibearch" >> /mnt/etc/hosts

    # Пароль root
    echo -e "${GREEN}Задай пароль для root:${NC}"
    arch-chroot /mnt passwd
}

# --- Установка загрузчика (GRUB + Dual Boot) ---
install_grub() {
    echo -e "${YELLOW}Ставлю GRUB...${NC}"
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr os-prober
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

    # Если есть Windows — добавляем в GRUB
    if lsblk -o FSTYPE | grep -i ntfs &>/dev/null; then
        echo -e "${GREEN}Найден Windows, добавляю в загрузчик...${NC}"
        echo "GRUB_DISABLE_OS_PROBER=false" >> /mnt/etc/default/grub
    fi

    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

# --- Создание пользователя ---
create_user() {
    echo -n "Введи имя пользователя: "
    read USERNAME
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"
    echo -e "${GREEN}Задай пароль для $USERNAME:${NC}"
    arch-chroot /mnt passwd "$USERNAME"

    # Sudo
    echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
}

# --- Дополнительные пакеты (сеть, звук) ---
install_extras() {
    arch-chroot /mnt pacman -S --noconfirm networkmanager sudo pipewire pulseaudio
    arch-chroot /mnt systemctl enable NetworkManager
}

# --- Графика (опционально) ---
install_gui() {
    read -p "Хочешь графическую оболочку? (y/N): " gui_choice
    if [[ $gui_choice == [yY] ]]; then
        echo -e "${GREEN}Ставлю GNOME...${NC}"
        arch-chroot /mnt pacman -S --noconfirm xorg gnome gnome-extra gdm
        arch-chroot /mnt systemctl enable gdm
    fi
}

# ===== ЗАПУСК =====
clear
echo -e "${GREEN}=== VibeArchInstall 2.0 (FULL AUTO) ===${NC}"

# 1. Выбор ядра
kernel_menu

# 2. Настройка сети
setup_network

# 3. Разметка диска
auto_partition

# 4. Установка Arch
install_arch

# 5. Настройка системы
configure_system

# 6. GRUB + Dual Boot
install_grub

# 7. Пользователь
create_user

# 8. Допы
install_extras

# 9. Графика (по желанию)
install_gui

# Готово!
echo -e "${GREEN}Установка завершена!${NC}"
echo -e "Команда для перезагрузки: ${YELLOW}umount -R /mnt && reboot${NC}"