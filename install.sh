#!/bin/sh

# Выбор языка / Language selection
echo "╔════════════════════════════════════╗"
echo "║     Выберите язык / Select language    ║"
echo "╠════════════════════════════════════╣"
echo "║ 1) Русский                         ║"
echo "║ 2) English                          ║"
echo "╚════════════════════════════════════╝"
echo ""

while true; do
    printf "Введите номер / Enter number (1-2): "
    read -r LANG_CHOICE
    
    case $LANG_CHOICE in
        1)
            LANG="ru"
            echo ""
            echo "Выбран русский язык"
            break
            ;;
        2)
            LANG="en"
            echo ""
            echo "English selected"
            break
            ;;
        *)
            echo "Ошибка / Error: введите 1 или 2 / enter 1 or 2"
            ;;
    esac
done

echo ""

# Функции для двуязычного вывода / Functions for bilingual output
msg() {
    if [ "$LANG" = "ru" ]; then
        printf "%s\n" "$1"
    else
        printf "%s\n" "$2"
    fi
}

msg_info() {
    if [ "$LANG" = "ru" ]; then
        printf "ℹ️ %s\n" "$1"
    else
        printf "ℹ️ %s\n" "$2"
    fi
}

msg_success() {
    if [ "$LANG" = "ru" ]; then
        printf "✅ %s\n" "$1"
    else
        printf "✅ %s\n" "$2"
    fi
}

msg_error() {
    if [ "$LANG" = "ru" ]; then
        printf "❌ %s\n" "$1"
    else
        printf "❌ %s\n" "$2"
    fi
    exit 1
}

msg_warning() {
    if [ "$LANG" = "ru" ]; then
        printf "⚠️ %s\n" "$1"
    else
        printf "⚠️ %s\n" "$2"
    fi
}

msg_important() {
    if [ "$LANG" = "ru" ]; then
        printf "\033[31;1m⚠️  %s\033[0m\n" "$1"
    else
        printf "\033[31;1m⚠️  %s\033[0m\n" "$2"
    fi
}

msg_prompt() {
    if [ "$LANG" = "ru" ]; then
        printf "%s" "$1"
    else
        printf "%s" "$2"
    fi
}

# Определяем версию OpenWRT / Detecting OpenWRT version
if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    msg "OpenWRT версия: $DISTRIB_RELEASE" "OpenWRT version: $DISTRIB_RELEASE"
    msg "Архитектура: $DISTRIB_ARCH" "Architecture: $DISTRIB_ARCH"
    msg "Название: $DISTRIB_DESCRIPTION" "Description: $DISTRIB_DESCRIPTION"
    msg "Кодовое имя: $DISTRIB_CODENAME" "Code name: $DISTRIB_CODENAME"
else
    msg_error "Это не OpenWRT или файл версии не найден" "This is not OpenWRT or version file not found"
fi

# Определяем менеджер пакетов / Detecting package manager
if command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
    msg "Менеджер пакетов: apk (новая версия)" "Package manager: apk (new version)"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MANAGER="opkg"
    msg "Менеджер пакетов: opkg (старая версия)" "Package manager: opkg (old version)"
else
    msg_error "Менеджер пакетов не найден" "Package manager not found"
fi

echo ""
msg "Система готова к установке." "System is ready for installation."

# Обновление списка пакетов / Updating package list
echo ""
msg "Обновление списка пакетов..." "Updating package list..."

if [ "$PKG_MANAGER" = "apk" ]; then
    apk update
else
    opkg update
fi

# Проверка и установка необходимых пакетов / Checking and installing required packages
echo ""
msg "Проверка необходимых пакетов..." "Checking required packages..."

packages="parted dosfstools blkid rsync"

for pkg in $packages; do
    if [ "$LANG" = "ru" ]; then
        printf "Проверка %s... " "$pkg"
    else
        printf "Checking %s... " "$pkg"
    fi
    
    if [ "$PKG_MANAGER" = "apk" ]; then
        if apk info -e "$pkg" >/dev/null 2>&1; then
            msg "установлен" "installed"
        else
            msg "не установлен. Устанавливаю..." "not installed. Installing..."
            apk add "$pkg"
        fi
    else
        if opkg list-installed | grep -q "^$pkg "; then
            msg "установлен" "installed"
        else
            msg "не установлен. Устанавливаю..." "not installed. Installing..."
            opkg install "$pkg"
        fi
    fi
done

echo ""
msg "Все необходимые пакеты установлены." "All required packages are installed."

# Исправление проблем с GPT перед сканированием / Fix GPT issues before scanning
msg_info "Проверка и исправление таблиц разделов..." "Checking and fixing partition tables..."

# Получаем список дисков через parted и исправляем GPT
parted -l 2>/dev/null | grep "^Disk /dev/" | grep -v "loop\|ram\|sr" | while read -r line; do
    disk=$(echo "$line" | cut -d' ' -f2 | tr -d ':')
    echo "fix" | parted ---pretend-input-tty $disk print >/dev/null 2>&1
done

# Получаем список дисков через parted / Getting disk list via parted
echo ""
msg "Выберите диск для установки OpenWRT:" "Select disk for OpenWRT installation:"
echo "----------------------------------------"

# Функция получения модели диска / Function to get disk model (без lsblk)
get_disk_model() {
    local disk="$1"
    if [ -f "/sys/block/$(basename "$disk")/device/model" ]; then
        cat "/sys/block/$(basename "$disk")/device/model" 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//'
    else
        echo "модель неизвестна / unknown model"
    fi
}

# Создаем временный файл для списка дисков / Create temporary file for disk list
TMP_DISKS=$(mktemp)

# Получаем список дисков (исключаем loop-устройства и cdrom) / Get disk list (exclude loop devices and cdrom)
parted -l 2>/dev/null | grep "^Disk /dev/" | grep -v "loop\|ram\|sr" | while read -r line; do
    disk=$(echo "$line" | cut -d' ' -f2 | tr -d ':')
    size=$(echo "$line" | cut -d' ' -f3)
    model=$(get_disk_model "$disk")
    echo "$disk|$size|$model" >> "$TMP_DISKS"
done

# Проверяем, что диски найдены / Check if disks found
if [ ! -s "$TMP_DISKS" ]; then
    msg_error "Диски не найдены" "No disks found"
fi

# Показываем диски с моделями / Show disks with models
printf "%-3s %-12s %-10s %s\n" "№" "Диск" "Размер" "Модель"
echo "----------------------------------------"

i=1
while IFS='|' read -r disk size model; do
    # Обрезаем модель, если слишком длинная
    if [ ${#model} -gt 30 ]; then
        model="${model:0:27}..."
    fi
    printf "%-3s %-12s %-10s %s\n" "$i)" "$disk" "$size" "$model"
    i=$((i + 1))
done < "$TMP_DISKS"

echo "----------------------------------------"
echo ""

DISK_COUNT=$((i - 1))

# Запрашиваем выбор диска / Ask for disk selection
while true; do
    msg_prompt "Выберите номер диска для установки (1-$DISK_COUNT): " "Select disk number for installation (1-$DISK_COUNT): "
    read -r CHOICE

    # Проверяем, что введено число / Check if input is a number
    if ! echo "$CHOICE" | grep -q '^[0-9]\+$'; then
        msg "Ошибка: введите число" "Error: enter a number"
        continue
    fi

    # Проверяем, что число в диапазоне / Check if number is in range
    if [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$DISK_COUNT" ]; then
        msg "Ошибка: введите число от 1 до $DISK_COUNT" "Error: enter a number from 1 to $DISK_COUNT"
        continue
    fi

    break
done

# Получаем выбранный диск / Get selected disk
SELECTED_DISK=$(sed -n "${CHOICE}p" "$TMP_DISKS" | cut -d'|' -f1)
SELECTED_MODEL=$(sed -n "${CHOICE}p" "$TMP_DISKS" | cut -d'|' -f3)
SELECTED_SIZE=$(sed -n "${CHOICE}p" "$TMP_DISKS" | cut -d'|' -f2)
rm -f "$TMP_DISKS"

echo ""
msg "Выбран диск: $SELECTED_DISK" "Selected disk: $SELECTED_DISK"
msg "Модель: $SELECTED_MODEL" "Model: $SELECTED_MODEL"
msg "Размер: $SELECTED_SIZE" "Size: $SELECTED_SIZE"
echo ""

# Создание GPT таблицы и разделов / Creating GPT table and partitions
echo ""
msg_warning "Создание разделов на $SELECTED_DISK..." "Creating partitions on $SELECTED_DISK..."
msg_warning "ВНИМАНИЕ: Все данные на диске будут уничтожены!" "WARNING: All data on the disk will be destroyed!"
echo ""

# Финальное предупреждение перед записью / Final warning before writing
msg_prompt "Продолжить? (yes/no): " "Continue? (yes/no): "
read -r CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    msg_error "Операция отменена" "Operation cancelled"
fi

# Создаем GPT таблицу / Create GPT table
echo ""
msg "Создание GPT таблицы разделов..." "Creating GPT partition table..."
if parted -s "$SELECTED_DISK" mklabel gpt; then
    msg_success "GPT таблица создана успешно" "GPT table created successfully"
else
    msg_error "Ошибка при создании GPT таблицы" "Error creating GPT table"
fi

# Создаем EFI раздел (256 МБ) / Create EFI partition (256 MB)
echo ""
msg "Создание EFI раздела (256 МБ)..." "Creating EFI partition (256 MB)..."
if parted -s "$SELECTED_DISK" mkpart primary fat32 1MiB 256MiB; then
    msg_success "EFI раздел создан" "EFI partition created"
else
    msg_error "Ошибка при создании EFI раздела" "Error creating EFI partition"
fi

# Устанавливаем флаг ESP / Set ESP flag
if parted -s "$SELECTED_DISK" set 1 esp on; then
    msg_success "Флаг ESP установлен на раздел 1" "ESP flag set on partition 1"
else
    msg_error "Ошибка при установке флага ESP" "Error setting ESP flag"
fi

# Создаем DATA раздел (всё оставшееся место) / Create DATA partition (all remaining space)
echo ""
msg "Создание DATA раздела на оставшемся месте..." "Creating DATA partition on remaining space..."
if parted -s "$SELECTED_DISK" mkpart primary ext4 257MiB 100%; then
    msg_success "DATA раздел создан на оставшемся месте" "DATA partition created on remaining space"
else
    msg_error "Ошибка при создании DATA раздела" "Error creating DATA partition"
fi

# Показываем итоговую таблицу разделов / Show final partition table
echo ""
msg "Итоговая таблица разделов:" "Final partition table:"
parted -s "$SELECTED_DISK" print

# Определяем имена разделов / Determine partition names
if echo "$SELECTED_DISK" | grep -q "nvme\|mmcblk"; then
    EFI_PART="${SELECTED_DISK}p1"
    DATA_PART="${SELECTED_DISK}p2"
else
    EFI_PART="${SELECTED_DISK}1"
    DATA_PART="${SELECTED_DISK}2"
fi

# Форматирование разделов / Formatting partitions
echo ""
msg "Форматирование разделов..." "Formatting partitions..."

# Форматирование EFI раздела (FAT32) / Format EFI partition (FAT32)
msg "Форматирование EFI раздела $EFI_PART в FAT32..." "Formatting EFI partition $EFI_PART as FAT32..."
if mkfs.fat -F 32 -n EFI "$EFI_PART"; then
    msg_success "EFI раздел отформатирован в FAT32 с меткой 'EFI'" "EFI partition formatted as FAT32 with label 'EFI'"
else
    msg_error "Ошибка при форматировании EFI раздела" "Error formatting EFI partition"
fi

# Форматирование DATA раздела (ext4) / Format DATA partition (ext4)
echo ""
msg "Форматирование DATA раздела $DATA_PART в ext4..." "Formatting DATA partition $DATA_PART as ext4..."
if mkfs.ext4 -F -L DATA "$DATA_PART"; then
    msg_success "DATA раздел отформатирован в ext4 с меткой 'DATA'" "DATA partition formatted as ext4 with label 'DATA'"
else
    msg_error "Ошибка при форматировании DATA раздела" "Error formatting DATA partition"
fi

echo ""
msg_success "Все разделы успешно отформатированы." "All partitions formatted successfully."

# Поиск дисков с OpenWRT / Searching for disks with OpenWRT
echo ""
msg "Поиск дисков с OpenWRT..." "Searching for disks with OpenWRT..."
echo "----------------------------------------"

TMP_RESULT=$(mktemp)

parted -l 2>/dev/null | grep "^Disk /dev/" | grep -v "loop\|ram\|sr" | while read -r line; do
    disk=$(echo "$line" | cut -d' ' -f2 | tr -d ':')
    
    # Создаем временную точку монтирования / Create temporary mount point
    mkdir -p /tmp/check_openwrt
    
    # Пробуем смонтировать второй раздел / Try to mount second partition
    if mount "${disk}2" /tmp/check_openwrt 2>/dev/null; then
        
        # Проверяем характерные для OpenWRT файлы / Check for OpenWRT specific files
        if [ -f "/tmp/check_openwrt/etc/openwrt_release" ] || \
           [ -f "/tmp/check_openwrt/etc/banner" ] || \
           [ -d "/tmp/check_openwrt/etc/opkg" ]; then
            msg_success "$disk — обнаружена OpenWRT (СИСТЕМНЫЙ ДИСК)" "$disk — OpenWRT found (SYSTEM DISK)"
            echo "$disk" > "$TMP_RESULT"
        else
            msg "   $disk — есть раздел, но не OpenWRT" "   $disk — partition exists but not OpenWRT"
        fi
        umount /tmp/check_openwrt
    else
        msg "   $disk — не удалось смонтировать второй раздел" "   $disk — failed to mount second partition"
    fi
    echo ""
done

rmdir /tmp/check_openwrt 2>/dev/null

# Читаем результат / Read result
if [ -s "$TMP_RESULT" ]; then
    SYSTEM_DISK=$(cat "$TMP_RESULT")
    rm -f "$TMP_RESULT"
    msg_success "OpenWRT установлена на: $SYSTEM_DISK" "OpenWRT installed on: $SYSTEM_DISK"
else
    rm -f "$TMP_RESULT"
    msg_error "Не удалось определить диск с OpenWRT" "Failed to determine disk with OpenWRT"
fi

# Устанавливаем TARGET_DISK из SELECTED_DISK / Set TARGET_DISK from SELECTED_DISK
TARGET_DISK="$SELECTED_DISK"

# Проверяем, что диски разные / Check if disks are different
if [ "$SYSTEM_DISK" = "$TARGET_DISK" ]; then
    msg_error "Ошибка: системный и целевой диски совпадают!" "Error: system and target disks are the same!"
fi

echo ""
msg "Начинаем копирование:" "Starting copy:"
msg "  СИСТЕМНЫЙ диск: $SYSTEM_DISK (USB-флешка)" "  SYSTEM disk: $SYSTEM_DISK (USB flash)"
msg "  ЦЕЛЕВОЙ диск: $TARGET_DISK (внутренний)" "  TARGET disk: $TARGET_DISK (internal)"
echo ""

# Определяем имена разделов для копирования / Determine partition names for copying
if echo "$SYSTEM_DISK" | grep -q "nvme\|mmcblk"; then
    SRC_EFI="${SYSTEM_DISK}p1"
    SRC_DATA="${SYSTEM_DISK}p2"
else
    SRC_EFI="${SYSTEM_DISK}1"
    SRC_DATA="${SYSTEM_DISK}2"
fi

if echo "$TARGET_DISK" | grep -q "nvme\|mmcblk"; then
    DST_EFI="${TARGET_DISK}p1"
    DST_DATA="${TARGET_DISK}p2"
else
    DST_EFI="${TARGET_DISK}1"
    DST_DATA="${TARGET_DISK}2"
fi

# Создаем точки монтирования / Create mount points
mkdir -p /mnt/src_efi /mnt/src_data /mnt/dst_efi /mnt/dst_data

# Монтируем исходные разделы / Mount source partitions
msg "Монтирование исходных разделов..." "Mounting source partitions..."
mount "$SRC_EFI" /mnt/src_efi || msg_error "Ошибка монтирования EFI раздела" "Error mounting EFI partition"
mount "$SRC_DATA" /mnt/src_data || msg_error "Ошибка монтирования DATA раздела" "Error mounting DATA partition"

# Монтируем целевые разделы / Mount target partitions
msg "Монтирование целевых разделов..." "Mounting target partitions..."
mount "$DST_EFI" /mnt/dst_efi || msg_error "Ошибка монтирования целевого EFI раздела" "Error mounting target EFI partition"
mount "$DST_DATA" /mnt/dst_data || msg_error "Ошибка монтирования целевого DATA раздела" "Error mounting target DATA partition"

# Копирование EFI раздела / Copying EFI partition
echo ""
msg "Копирование EFI раздела..." "Copying EFI partition..."

if ! command -v rsync >/dev/null 2>&1; then
    cp -a /mnt/src_efi/* /mnt/dst_efi/
else
    rsync -a /mnt/src_efi/ /mnt/dst_efi/
fi

if [ $? -eq 0 ]; then
    msg_success "EFI раздел скопирован" "EFI partition copied"
else
    msg_error "Ошибка копирования EFI раздела" "Error copying EFI partition"
fi

# Копирование DATA раздела / Copying DATA partition
echo ""
msg "Копирование DATA раздела (это может занять некоторое время)..." "Copying DATA partition (this may take a while)..."

# ПРОСТОЕ КОПИРОВАНИЕ БЕЗ ЛЮБЫХ ПРОГРЕСС-БАРОВ
if ! command -v rsync >/dev/null 2>&1; then
    cp -a /mnt/src_data/* /mnt/dst_data/
    COPY_RESULT=$?
else
    rsync -a /mnt/src_data/ /mnt/dst_data/
    COPY_RESULT=$?
fi

if [ $COPY_RESULT -eq 0 ]; then
    msg_success "DATA раздел скопирован" "DATA partition copied"
    
    # Показываем итоговую статистику / Show final statistics
    DST_FILES=$(find /mnt/dst_data -type f | wc -l)
    msg "Скопировано файлов: $DST_FILES" "Files copied: $DST_FILES"
    
    SRC_SIZE=$(du -sh /mnt/src_data | cut -f1)
    msg "Размер данных: $SRC_SIZE" "Data size: $SRC_SIZE"
else
    msg_error "Ошибка копирования DATA раздела" "Error copying DATA partition"
fi

# Обновление PARTUUID в grub.cfg / Updating PARTUUID in grub.cfg
echo ""
msg "Поиск PARTUUID второго раздела целевого диска..." "Searching PARTUUID of target disk second partition..."

if echo "$TARGET_DISK" | grep -q "nvme\|mmcblk"; then
    TARGET_PART2="${TARGET_DISK}p2"
else
    TARGET_PART2="${TARGET_DISK}2"
fi

# Получаем PARTUUID / Get PARTUUID
TARGET_PARTUUID=$(blkid "$TARGET_PART2" | sed -n 's/.*PARTUUID="\([^"]*\)".*/\1/p')

if [ -z "$TARGET_PARTUUID" ]; then
    msg_error "Ошибка: не удалось получить PARTUUID для $TARGET_PART2" "Error: failed to get PARTUUID for $TARGET_PART2"
fi

msg_success "PARTUUID второго раздела: $TARGET_PARTUUID" "Second partition PARTUUID: $TARGET_PARTUUID"
echo ""

# Редактируем grub.cfg / Edit grub.cfg
GRUB_CFG="/mnt/dst_efi/boot/grub/grub.cfg"

if [ ! -f "$GRUB_CFG" ]; then
    msg_error "Ошибка: файл $GRUB_CFG не найден" "Error: file $GRUB_CFG not found"
fi

# Создаем резервную копию / Create backup
cp "$GRUB_CFG" "${GRUB_CFG}.bak"
msg "  ✓ Создана резервная копия: ${GRUB_CFG}.bak" "  ✓ Backup created: ${GRUB_CFG}.bak"

# Заменяем PARTUUID / Replace PARTUUID
if sed -i "s/[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}/$TARGET_PARTUUID/g" "$GRUB_CFG"; then
    msg_success "PARTUUID заменены в grub.cfg" "PARTUUID replaced in grub.cfg"
else
    msg_error "Ошибка при замене PARTUUID" "Error replacing PARTUUID"
fi

# Показываем результат / Show result
echo ""
msg "Первые несколько строк измененного grub.cfg:" "First few lines of modified grub.cfg:"
head -20 "$GRUB_CFG" | grep -i "PARTUUID" --color=always

echo ""
msg_success "PARTUUID успешно обновлены в grub.cfg" "PARTUUID successfully updated in grub.cfg"

# Размонтирование / Unmounting
echo ""
msg "Размонтирование разделов..." "Unmounting partitions..."
umount /mnt/src_efi /mnt/src_data /mnt/dst_efi /mnt/dst_data

echo ""
msg_success "Установка успешно завершена!" "Installation completed successfully!"
msg "Можно перезагружать систему с нового диска." "You can now reboot from the new disk."
echo ""
msg_important "ВАЖНО: После перезагрузки зайдите в BIOS/Boot Menu" "IMPORTANT: After reboot, enter BIOS/Boot Menu"
msg_important "   и выберите новый диск как загрузочный." "   and select the new disk as boot device."
echo ""
msg_important "   Обычно для этого нужно нажать F2, F10, F12 или DEL" "   Usually you need to press F2, F10, F12 or DEL"
msg_important "   сразу после включения компьютера." "   immediately after turning on the computer."
