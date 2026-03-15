#!/bin/sh

# OpenWRT USB to Internal Disk Installer (x86)
# Version: 2.0
# Author: Rever-end
# License: MIT

# ========== ЦВЕТА ДЛЯ ВЫВОДА ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ========== ОБРАБОТКА ПРЕРЫВАНИЙ ==========
cleanup_on_exit() {
    echo -e "\n${YELLOW}Прерывание! Выполняю очистку...${NC}"
    umount /mnt/efi 2>/dev/null
    umount /mnt/data 2>/dev/null
    umount /mnt/source_boot 2>/dev/null
    umount /mnt/source_data 2>/dev/null
    log "INFO" "Скрипт прерван пользователем"
    exit 1
}

trap cleanup_on_exit INT TERM

# ========== ПЕРЕМЕННЫЕ ==========
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
LOG_DIR="/tmp/openwrt_installer"
LOG_FILE="$LOG_DIR/install_$(date +%Y%m%d_%H%M%S).log"
LANG=""
SELECTED_DISK=""
SOURCE_DISK=""
TARGET_DISK=""

# ========== ФУНКЦИИ ==========

# Создание директории для логов
setup_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Скрипт запущен" >> "$LOG_FILE"
}

# Логирование
log() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message" >> "$LOG_FILE"
}

# Обработка ошибок
error_exit() {
    local message="$1"
    echo -e "${RED}${message}${NC}" >&2
    log "ERROR" "$message"
    
    # Предложить просмотр лога
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Хотите открыть лог для просмотра? (y/n): ${NC}"
    else
        echo -e "${YELLOW}Do you want to open the log for viewing? (y/n): ${NC}"
    fi
    read -p "" VIEW_LOG
    
    if [ "$VIEW_LOG" = "y" ] || [ "$VIEW_LOG" = "Y" ]; then
        if command -v nano >/dev/null 2>&1; then
            nano "$LOG_FILE"
        elif command -v vi >/dev/null 2>&1; then
            vi "$LOG_FILE"
        elif command -v vim >/dev/null 2>&1; then
            vim "$LOG_FILE"
        elif command -v less >/dev/null 2>&1; then
            less "$LOG_FILE"
        else
            cat "$LOG_FILE"
        fi
    fi
    
    exit 1
}

# Выбор языка
choose_language() {
    echo "Please choose your language / Пожалуйста, выберите язык:"
    echo "1) Русский"
    echo "2) English"
    read -p "Enter 1 or 2 / Введите 1 или 2: " LANG_CHOICE
    
    case $LANG_CHOICE in
        1)
            LANG="ru"
            echo -e "${GREEN}Выбран русский язык${NC}"
            log "INFO" "Выбран русский язык"
            ;;
        2)
            LANG="en"
            echo -e "${GREEN}English selected${NC}"
            log "INFO" "English selected"
            ;;
        *)
            echo -e "${RED}Invalid choice / Неверный выбор. Default: English${NC}"
            LANG="en"
            log "WARNING" "Invalid language choice, defaulting to English"
            ;;
    esac
}

# ========== ФУНКЦИЯ ПРОВЕРКИ ИНТЕРНЕТА ==========
check_internet() {
    log "INFO" "Проверка подключения к интернету..."
    
    # Цели для проверки (без массивов, совместимо с ash)
    local targets="1.1.1.1 9.9.9.9 openwrt.org kernel.org"
    local success=0
    
    for target in $targets; do
        if ping -c 1 -W 3 "$target" >/dev/null 2>&1; then
            log "INFO" "Доступен: $target"
            success=1
            break
        else
            log "INFO" "Недоступен: $target"
        fi
    done
    
    # Если ping не сработал, пробуем curl (на случай блокировки ICMP)
    if [ $success -eq 0 ] && command -v curl >/dev/null 2>&1; then
        log "INFO" "Пинг не сработал, пробуем curl..."
        if curl -s --connect-timeout 3 "http://1.1.1.1" >/dev/null 2>&1; then
            log "INFO" "HTTP доступен через 1.1.1.1"
            success=1
        fi
    fi
    
    if [ $success -eq 1 ]; then
        log "INFO" "Интернет доступен"
        return 0
    else
        log "ERROR" "Интернет не обнаружен"
        return 1
    fi
}

# Установка необходимых пакетов
install_packages() {
    log "INFO" "Установка необходимых пакетов..."
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Установка необходимых пакетов...${NC}"
    else
        echo -e "${YELLOW}Installing required packages...${NC}"
    fi
    
    # Определяем менеджер пакетов (apk или opkg)
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add"
        log "INFO" "Используется apk (новые версии OpenWRT)"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        PKG_UPDATE="opkg update"
        PKG_INSTALL="opkg install"
        log "INFO" "Используется opkg (старые версии OpenWRT)"
    else
        log "WARNING" "Не найден менеджер пакетов"
        if [ "$LANG" = "ru" ]; then
            echo -e "${RED}Не найден менеджер пакетов (apk/opkg)${NC}"
        else
            echo -e "${RED}No package manager found (apk/opkg)${NC}"
        fi
        return 1
    fi
    
    # Список необходимых пакетов
    PACKAGES="sfdisk dosfstools rsync blkid nano parted"
    
    # Обновление списка пакетов
    log "INFO" "Обновление списка пакетов..."
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Обновление списка пакетов...${NC}"
    else
        echo -e "${YELLOW}Updating package list...${NC}"
    fi
    
    eval $PKG_UPDATE >> "$LOG_FILE" 2>&1
    
    # Установка пакетов по одному
    for pkg in $PACKAGES; do
        log "INFO" "Установка $pkg..."
        if [ "$LANG" = "ru" ]; then
            echo -e "${YELLOW}Установка $pkg...${NC}"
        else
            echo -e "${YELLOW}Installing $pkg...${NC}"
        fi
        
        eval $PKG_INSTALL $pkg >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            log "WARNING" "Не удалось установить $pkg"
            if [ "$LANG" = "ru" ]; then
                echo -e "${RED}Не удалось установить $pkg${NC}"
            else
                echo -e "${RED}Failed to install $pkg${NC}"
            fi
        else
            log "INFO" "$pkg установлен"
            if [ "$LANG" = "ru" ]; then
                echo -e "${GREEN}$pkg установлен${NC}"
            else
                echo -e "${GREEN}$pkg installed${NC}"
            fi
        fi
    done
    
    log "INFO" "Установка пакетов завершена"
    if [ "$LANG" = "ru" ]; then
        echo -e "${GREEN}Установка пакетов завершена${NC}"
    else
        echo -e "${GREEN}Package installation completed${NC}"
    fi
}

# Проверка наличия необходимых команд
check_required_commands() {
    local missing=""
    
    if ! command -v sfdisk >/dev/null 2>&1; then
        missing="$missing sfdisk"
    fi
    if ! command -v mkfs.ext4 >/dev/null 2>&1; then
        missing="$missing mkfs.ext4"
    fi
    
    if [ -n "$missing" ]; then
        error_exit "Missing required commands:$missing / Отсутствуют необходимые команды:$missing"
    fi
}

# ========== ВЫБОР ЦЕЛЕВОГО ДИСКА (КУДА УСТАНАВЛИВАТЬ) ==========
select_target_disk() {
    log "INFO" "Выбор целевого диска для установки"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${YELLOW}=== ВЫБЕРИТЕ ДИСК, КУДА БУДЕТ УСТАНОВЛЕНА СИСТЕМА ===${NC}"
        echo -e "${RED}ВНИМАНИЕ: Все данные на этом диске будут уничтожены!${NC}\n"
    else
        echo -e "\n${YELLOW}=== SELECT TARGET DISK FOR INSTALLATION ===${NC}"
        echo -e "${RED}WARNING: All data on this disk will be destroyed!${NC}\n"
    fi
    
    # Получаем список дисков через /sys/block
    DISK_LIST=""
    DISK_COUNT=0
    
    for disk in /sys/block/*; do
        disk_name=$(basename "$disk")
        # Пропускаем loop-устройства и RAM-диски
        case "$disk_name" in
            loop*|ram*|sr*) continue ;;
        esac
        
        # Получаем размер диска
        if [ -f "$disk/size" ]; then
            size_sectors=$(cat "$disk/size")
            size_bytes=$((size_sectors * 512))
            if command -v numfmt >/dev/null 2>&1; then
                size_human=$(numfmt --to=iec "$size_bytes")
            else
                size_human="$size_bytes bytes"
            fi
        else
            size_human="Unknown"
        fi
        
        # Получаем модель диска (если есть)
        model=""
        if [ -f "$disk/device/model" ]; then
            model=$(cat "$disk/device/model")
        fi
        
        # Проверяем, не является ли диск съёмным
        removable=""
        if [ -f "$disk/removable" ]; then
            if [ "$(cat "$disk/removable")" = "1" ]; then
                removable=" [USB]"
            fi
        fi
        
        DISK_COUNT=$((DISK_COUNT + 1))
        DISK_LIST="$DISK_LIST $disk_name"
        
        echo "$DISK_COUNT) /dev/$disk_name - $model ($size_human)$removable"
    done
    
    if [ $DISK_COUNT -eq 0 ]; then
        error_exit "No disks found / Не найдено дисков"
    fi
    
    # Выбор диска
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${YELLOW}Введите номер диска для установки OpenWRT:${NC}"
    else
        echo -e "\n${YELLOW}Enter disk number for OpenWRT installation:${NC}"
    fi
    read -p "> " DISK_NUM
    
    # Проверка ввода
    if ! echo "$DISK_NUM" | grep -qE '^[0-9]+$' || [ "$DISK_NUM" -lt 1 ] || [ "$DISK_NUM" -gt "$DISK_COUNT" ]; then
        error_exit "Invalid disk number / Неверный номер диска"
    fi
    
    # Получаем выбранный диск
    SELECTED_DISK="/dev/$(echo $DISK_LIST | cut -d' ' -f $DISK_NUM)"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Выбран диск для установки: ${RED}${SELECTED_DISK}${NC}"
    else
        echo -e "${YELLOW}Selected target disk: ${RED}${SELECTED_DISK}${NC}"
    fi
    
    log "INFO" "Выбран целевой диск: $SELECTED_DISK"
    
    # Подтверждение
    if [ "$LANG" = "ru" ]; then
        read -p "$(echo -e "${YELLOW}Установить OpenWRT на этот диск? (y/N): ${NC}")" CONFIRM
    else
        read -p "$(echo -e "${YELLOW}Install OpenWRT on this disk? (y/N): ${NC}")" CONFIRM
    fi
    
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        error_exit "Operation cancelled / Операция отменена"
    fi
    
    # Финальное предупреждение
    echo -e "\n${RED}WARNING: ALL DATA ON $SELECTED_DISK WILL BE DESTROYED!${NC}"
    echo -e "${RED}ПРЕДУПРЕЖДЕНИЕ: ВСЕ ДАННЫЕ НА $SELECTED_DISK БУДУТ УНИЧТОЖЕНЫ!${NC}\n"
    
    if [ "$LANG" = "ru" ]; then
        read -p "$(echo -e "${RED}Введите 'yes' для подтверждения форматирования: ${NC}")" FINAL_CONFIRM
    else
        read -p "$(echo -e "${RED}Type 'yes' to confirm formatting: ${NC}")" FINAL_CONFIRM
    fi
    
    if [ "$FINAL_CONFIRM" != "yes" ]; then
        error_exit "Operation cancelled / Операция отменена"
    fi
    
    TARGET_DISK="$SELECTED_DISK"
    log "INFO" "Финальное подтверждение получено, целевой диск: $TARGET_DISK"
}

# ========== ОПРЕДЕЛЕНИЕ ИСХОДНОГО ДИСКА (ОТКУДА КОПИРОВАТЬ) ==========
find_source_disk() {
    log "INFO" "Поиск исходного диска с OpenWRT"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${YELLOW}=== ПОИСК ИСХОДНОГО ДИСКА С OpenWRT ===${NC}"
        echo -e "${YELLOW}Определяем, с какого диска загружена система...${NC}\n"
    else
        echo -e "\n${YELLOW}=== LOOKING FOR SOURCE DISK WITH OpenWRT ===${NC}"
        echo -e "${YELLOW}Detecting boot disk...${NC}\n"
    fi
    
    # Ищем смонтированные разделы с boot и root
    BOOT_PART=""
    ROOT_PART=""
    
    # Проверяем монтирования в /proc/mounts
    while read -r line; do
        case "$line" in
            */boot*)
                BOOT_PART=$(echo "$line" | cut -d' ' -f1)
                log "INFO" "Найден boot раздел: $BOOT_PART"
                ;;
            */rom*|*/overlay*|*root*)
                if [ -z "$ROOT_PART" ]; then
                    ROOT_PART=$(echo "$line" | cut -d' ' -f1)
                    log "INFO" "Найден root раздел: $ROOT_PART"
                fi
                ;;
        esac
    done < /proc/mounts
    
    SOURCE_DISK=""
    
    # Если нашли оба раздела
    if [ -n "$BOOT_PART" ] && [ -n "$ROOT_PART" ]; then
        # Извлекаем имя диска из разделов
        BOOT_DISK=$(echo "$BOOT_PART" | sed 's/[0-9]*$//')
        ROOT_DISK=$(echo "$ROOT_PART" | sed 's/[0-9]*$//')
        
        if [ "$BOOT_DISK" = "$ROOT_DISK" ]; then
            SOURCE_DISK="$BOOT_DISK"
            log "INFO" "Найден исходный диск: $SOURCE_DISK"
        fi
    fi
    
    # Если не нашли через монтирования, пробуем найти диск с корневой файловой системой
    if [ -z "$SOURCE_DISK" ]; then
        # Ищем диск, на котором есть файл /etc/openwrt_release
        for disk in /sys/block/*; do
            disk_name=$(basename "$disk")
            case "$disk_name" in
                loop*|ram*|sr*) continue ;;
            esac
            
            # Проверяем первый раздел
            if [ -b "/dev/${disk_name}1" ]; then
                mkdir -p /mnt/check_source
                if mount "/dev/${disk_name}1" /mnt/check_source 2>/dev/null; then
                    if [ -f "/mnt/check_source/etc/openwrt_release" ] || [ -d "/mnt/check_source/rom" ]; then
                        SOURCE_DISK="/dev/$disk_name"
                        umount /mnt/check_source 2>/dev/null
                        log "INFO" "Найден диск с OpenWRT через проверку: $SOURCE_DISK"
                        break
                    fi
                    umount /mnt/check_source 2>/dev/null
                fi
            fi
        done
        rmdir /mnt/check_source 2>/dev/null
    fi
    
    # Если нашли диск
    if [ -n "$SOURCE_DISK" ]; then
        # Получаем модель диска для красивого вывода
        disk_name=$(basename "$SOURCE_DISK")
        model=""
        if [ -f "/sys/block/$disk_name/device/model" ]; then
            model=$(cat "/sys/block/$disk_name/device/model")
        fi
        
        if [ "$LANG" = "ru" ]; then
            echo -e "${GREEN}Найден диск с OpenWRT: $SOURCE_DISK $model${NC}"
            echo -e "${YELLOW}Будет использован этот диск для копирования системы.${NC}"
            read -p "$(echo -e "${YELLOW}Продолжить? (Y/n): ${NC}")" SOURCE_CONFIRM
        else
            echo -e "${GREEN}Found OpenWRT disk: $SOURCE_DISK $model${NC}"
            echo -e "${YELLOW}This disk will be used as source for copying.${NC}"
            read -p "$(echo -e "${YELLOW}Continue? (Y/n): ${NC}")" SOURCE_CONFIRM
        fi
        
        # По умолчанию Y, если пользователь нажал Enter
        if [ -z "$SOURCE_CONFIRM" ] || [ "$SOURCE_CONFIRM" = "y" ] || [ "$SOURCE_CONFIRM" = "Y" ]; then
            log "INFO" "Исходный диск подтверждён: $SOURCE_DISK"
            if [ "$LANG" = "ru" ]; then
                echo -e "${GREEN}Исходный диск: $SOURCE_DISK${NC}\n"
            else
                echo -e "${GREEN}Source disk: $SOURCE_DISK${NC}\n"
            fi
            return 0
        else
            if [ "$LANG" = "ru" ]; then
                echo -e "${YELLOW}Операция отменена пользователем.${NC}"
            else
                echo -e "${YELLOW}Operation cancelled by user.${NC}"
            fi
            exit 1
        fi
    fi
    
    # Если не нашли автоматически, показываем список дисков для выбора
    log "ERROR" "Не удалось автоматически найти исходный диск с OpenWRT"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${RED}Не удалось автоматически определить диск с OpenWRT${NC}"
        echo -e "${YELLOW}Пожалуйста, выберите диск, с которого нужно скопировать систему:${NC}\n"
    else
        echo -e "\n${RED}Could not automatically detect OpenWRT disk${NC}"
        echo -e "${YELLOW}Please select the source disk to copy system from:${NC}\n"
    fi
    
    # Получаем список всех дисков
    SOURCE_DISKS=""
    SOURCE_COUNT=0
    
    for disk in /sys/block/*; do
        disk_name=$(basename "$disk")
        case "$disk_name" in
            loop*|ram*|sr*) continue ;;
        esac
        
        # Пропускаем целевой диск
        if [ "/dev/$disk_name" = "$TARGET_DISK" ]; then
            continue
        fi
        
        # Получаем размер диска
        if [ -f "$disk/size" ]; then
            size_sectors=$(cat "$disk/size")
            size_bytes=$((size_sectors * 512))
            if command -v numfmt >/dev/null 2>&1; then
                size_human=$(numfmt --to=iec "$size_bytes")
            else
                size_human="$size_bytes bytes"
            fi
        else
            size_human="Unknown"
        fi
        
        # Получаем модель диска
        model=""
        if [ -f "$disk/device/model" ]; then
            model=$(cat "$disk/device/model")
        fi
        
        SOURCE_COUNT=$((SOURCE_COUNT + 1))
        SOURCE_DISKS="$SOURCE_DISKS /dev/$disk_name"
        
        echo "$SOURCE_COUNT) /dev/$disk_name - $model ($size_human)"
    done
    
    if [ $SOURCE_COUNT -eq 0 ]; then
        error_exit "No source disks found / Не найдено исходных дисков"
    fi
    
    # Если только один вариант
    if [ $SOURCE_COUNT -eq 1 ]; then
        SOURCE_DISK=$(echo $SOURCE_DISKS | tr ' ' '\n' | sed -n "1p")
        if [ "$LANG" = "ru" ]; then
            echo -e "\n${GREEN}Найден единственный возможный диск: $SOURCE_DISK${NC}"
            read -p "$(echo -e "${YELLOW}Использовать этот диск? (Y/n): ${NC}")" SOURCE_CONFIRM
        else
            echo -e "\n${GREEN}Found only possible disk: $SOURCE_DISK${NC}"
            read -p "$(echo -e "${YELLOW}Use this disk? (Y/n): ${NC}")" SOURCE_CONFIRM
        fi
        
        if [ -z "$SOURCE_CONFIRM" ] || [ "$SOURCE_CONFIRM" = "y" ] || [ "$SOURCE_CONFIRM" = "Y" ]; then
            log "INFO" "Исходный диск выбран из единственного варианта: $SOURCE_DISK"
            if [ "$LANG" = "ru" ]; then
                echo -e "${GREEN}Выбран исходный диск: $SOURCE_DISK${NC}\n"
            else
                echo -e "${GREEN}Selected source disk: $SOURCE_DISK${NC}\n"
            fi
            return 0
        else
            error_exit "Operation cancelled / Операция отменена"
        fi
    fi
    
    # Если несколько вариантов - выбор по номеру
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${YELLOW}Введите номер диска для копирования системы:${NC}"
    else
        echo -e "\n${YELLOW}Enter source disk number:${NC}"
    fi
    read -p "> " SOURCE_NUM
    
    if ! echo "$SOURCE_NUM" | grep -qE '^[0-9]+$' || [ "$SOURCE_NUM" -lt 1 ] || [ "$SOURCE_NUM" -gt "$SOURCE_COUNT" ]; then
        error_exit "Invalid disk number / Неверный номер диска"
    fi
    
    SOURCE_DISK=$(echo $SOURCE_DISKS | tr ' ' '\n' | sed -n "${SOURCE_NUM}p")
    log "INFO" "Исходный диск выбран вручную: $SOURCE_DISK"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${GREEN}Выбран исходный диск: $SOURCE_DISK${NC}\n"
    else
        echo -e "${GREEN}Selected source disk: $SOURCE_DISK${NC}\n"
    fi
}

# ========== ПРОВЕРКА, ЧТО ДИСКИ РАЗНЫЕ ==========
check_disks_different() {
    if [ "$TARGET_DISK" = "$SOURCE_DISK" ]; then
        error_exit "Target disk is the same as source disk! / Целевой диск совпадает с исходным!"
    fi
}

# Создание разделов на целевом диске
create_partitions() {
    log "INFO" "Создание разделов на $TARGET_DISK"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Создание разделов на $TARGET_DISK...${NC}"
    else
        echo -e "${YELLOW}Creating partitions on $TARGET_DISK...${NC}"
    fi
    
    # Очистка существующей таблицы разделов и создание GPT
    log "INFO" "Очистка диска и создание GPT таблицы"
    dd if=/dev/zero of="$TARGET_DISK" bs=1M count=1 >> "$LOG_FILE" 2>&1
    
    # Создание разделов через sfdisk
    echo "label: gpt" | sfdisk "$TARGET_DISK" >> "$LOG_FILE" 2>&1
    
    # Создание EFI раздела (256 MB) с правильным типом для UEFI
    echo "size=256M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=\"EFI\"" | sfdisk -a "$TARGET_DISK" >> "$LOG_FILE" 2>&1
    
    # Создание DATA раздела на остатке
    echo "type=L, name=\"DATA\"" | sfdisk -a "$TARGET_DISK" >> "$LOG_FILE" 2>&1
    
    if [ $? -ne 0 ]; then
        error_exit "Failed to create partitions / Не удалось создать разделы"
    fi
    
    log "INFO" "Разделы созданы успешно"
    sleep 2  # Даем ядру время на обновление
    
    # Определение созданных разделов
    EFI_PART="${TARGET_DISK}1"
    DATA_PART="${TARGET_DISK}2"
    
    log "INFO" "EFI раздел: $EFI_PART, DATA раздел: $DATA_PART"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${GREEN}Разделы созданы:${NC}"
        echo "  EFI: $EFI_PART (256 MB, тип: EFI System)"
        echo "  DATA: $DATA_PART (остаток)"
    else
        echo -e "${GREEN}Partitions created:${NC}"
        echo "  EFI: $EFI_PART (256 MB, type: EFI System)"
        echo "  DATA: $DATA_PART (remaining)"
    fi
}

# ========== ФОРМАТИРОВАНИЕ РАЗДЕЛОВ ==========
format_partitions() {
    log "INFO" "Форматирование разделов"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Форматирование разделов...${NC}"
    else
        echo -e "${YELLOW}Formatting partitions...${NC}"
    fi
    
    # Проверяем, не примонтированы ли разделы
    if mount | grep -q "$EFI_PART"; then
        umount "$EFI_PART" 2>/dev/null
    fi
    if mount | grep -q "$DATA_PART"; then
        umount "$DATA_PART" 2>/dev/null
    fi
    
    # Определяем доступную команду для FAT
    FAT_CMD=""
    if command -v mkfs.fat >/dev/null 2>&1; then
        FAT_CMD="mkfs.fat"
        log "INFO" "Найдена команда mkfs.fat"
    elif command -v mkfs.vfat >/dev/null 2>&1; then
        FAT_CMD="mkfs.vfat"
        log "INFO" "Найдена команда mkfs.vfat"
    elif command -v mkfs.msdos >/dev/null 2>&1; then
        FAT_CMD="mkfs.msdos"
        log "INFO" "Найдена команда mkfs.msdos"
    else
        error_exit "No FAT formatter found (tried mkfs.fat, mkfs.vfat, mkfs.msdos)"
    fi
    
    log "INFO" "Используется команда для FAT: $FAT_CMD"
    
    # Форматирование EFI в FAT32
    log "INFO" "Форматирование $EFI_PART в FAT32"
    $FAT_CMD -F32 -n "EFI" "$EFI_PART" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        error_exit "Failed to format EFI partition / Не удалось отформатировать EFI раздел"
    fi
    
    # Установка флага ESP (хотя при создании мы уже задали правильный тип)
    if command -v parted >/dev/null 2>&1; then
        log "INFO" "Установка флага esp on через parted"
        parted "$TARGET_DISK" set 1 esp on >> "$LOG_FILE" 2>&1
    fi
    
    # Форматирование DATA в ext4
    log "INFO" "Форматирование $DATA_PART в ext4"
    mkfs.ext4 -F -L "DATA" "$DATA_PART" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        error_exit "Failed to format DATA partition / Не удалось отформатировать DATA раздел"
    fi
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${GREEN}Форматирование завершено${NC}"
    else
        echo -e "${GREEN}Formatting completed${NC}"
    fi
}

# Монтирование разделов
mount_partitions() {
    log "INFO" "Монтирование разделов"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Монтирование разделов...${NC}"
    else
        echo -e "${YELLOW}Mounting partitions...${NC}"
    fi
    
    # Создание точек монтирования
    mkdir -p /mnt/efi /mnt/data
    
    # Монтирование EFI
    mount "$EFI_PART" /mnt/efi >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        error_exit "Failed to mount EFI partition / Не удалось примонтировать EFI раздел"
    fi
    
    # Монтирование DATA
    mount "$DATA_PART" /mnt/data >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        umount /mnt/efi 2>/dev/null
        error_exit "Failed to mount DATA partition / Не удалось примонтировать DATA раздел"
    fi
    
    log "INFO" "Разделы примонтированы"
    if [ "$LANG" = "ru" ]; then
        echo -e "${GREEN}Разделы примонтированы${NC}"
    else
        echo -e "${GREEN}Partitions mounted${NC}"
    fi
}

# Копирование системы
copy_system() {
    log "INFO" "Копирование системы"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Копирование системы с исходного диска на целевой...${NC}"
    else
        echo -e "${YELLOW}Copying system from source disk to target...${NC}"
    fi
    
    # Определяем исходные разделы
    SOURCE_BOOT="${SOURCE_DISK}1"
    SOURCE_DATA="${SOURCE_DISK}2"
    
    # Проверяем, существуют ли разделы
    if [ ! -b "$SOURCE_BOOT" ]; then
        error_exit "Source boot partition not found: $SOURCE_BOOT / Исходный boot раздел не найден"
    fi
    if [ ! -b "$SOURCE_DATA" ]; then
        error_exit "Source data partition not found: $SOURCE_DATA / Исходный data раздел не найден"
    fi
    
    # Монтируем исходные разделы (если не смонтированы)
    mkdir -p /mnt/source_boot /mnt/source_data
    
    if ! mountpoint -q /mnt/source_boot; then
        mount "$SOURCE_BOOT" /mnt/source_boot >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            error_exit "Failed to mount source boot partition / Не удалось примонтировать исходный boot раздел"
        fi
    fi
    
    if ! mountpoint -q /mnt/source_data; then
        mount "$SOURCE_DATA" /mnt/source_data >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            umount /mnt/source_boot 2>/dev/null
            error_exit "Failed to mount source data partition / Не удалось примонтировать исходный data раздел"
        fi
    fi
    
    # Копирование boot раздела
    log "INFO" "Копирование boot раздела"
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Копирование boot раздела...${NC}"
    else
        echo -e "${YELLOW}Copying boot partition...${NC}"
    fi
    
    if command -v rsync >/dev/null 2>&1; then
        rsync -av --progress /mnt/source_boot/ /mnt/efi/ >> "$LOG_FILE" 2>&1
    else
        cp -a /mnt/source_boot/. /mnt/efi/ >> "$LOG_FILE" 2>&1
    fi
    
    if [ $? -ne 0 ]; then
        error_exit "Failed to copy boot partition / Не удалось скопировать boot раздел"
    fi
    
    # Копирование data раздела
    log "INFO" "Копирование data раздела"
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Копирование data раздела...${NC}"
    else
        echo -e "${YELLOW}Copying data partition...${NC}"
    fi
    
    if command -v rsync >/dev/null 2>&1; then
        rsync -av --progress /mnt/source_data/ /mnt/data/ >> "$LOG_FILE" 2>&1
    else
        cp -a /mnt/source_data/. /mnt/data/ >> "$LOG_FILE" 2>&1
    fi
    
    if [ $? -ne 0 ]; then
        error_exit "Failed to copy data partition / Не удалось скопировать data раздел"
    fi
    
    log "INFO" "Копирование завершено"
    if [ "$LANG" = "ru" ]; then
        echo -e "${GREEN}Копирование завершено${NC}"
    else
        echo -e "${GREEN}Copying completed${NC}"
    fi
    
    # Размонтирование исходных разделов
    umount /mnt/source_boot 2>/dev/null
    umount /mnt/source_data 2>/dev/null
    rmdir /mnt/source_boot /mnt/source_data 2>/dev/null
}

# Обновление PARTUUID в grub.cfg
update_partuuid() {
    log "INFO" "Обновление PARTUUID в grub.cfg"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Обновление PARTUUID в конфигурации загрузчика...${NC}"
    else
        echo -e "${YELLOW}Updating PARTUUID in bootloader configuration...${NC}"
    fi
    
    # Получаем PARTUUID для DATA раздела
    PARTUUID=""
    if command -v blkid >/dev/null 2>&1; then
        PARTUUID=$(blkid -s PARTUUID -o value "$DATA_PART")
    fi
    
    if [ -z "$PARTUUID" ] && command -v lsblk >/dev/null 2>&1; then
        PARTUUID=$(lsblk -no PARTUUID "$DATA_PART" 2>/dev/null)
    fi
    
    if [ -z "$PARTUUID" ] && [ -e "/sys/block/$(basename $DATA_PART)/partition_uuid" ]; then
        PARTUUID=$(cat "/sys/block/$(basename $DATA_PART)/partition_uuid")
    fi
    
    if [ -z "$PARTUUID" ]; then
        log "WARNING" "Не удалось получить PARTUUID, пропускаем обновление"
        if [ "$LANG" = "ru" ]; then
            echo -e "${RED}Не удалось получить PARTUUID, конфигурация загрузчика может быть некорректной${NC}"
        else
            echo -e "${RED}Failed to get PARTUUID, bootloader configuration may be incorrect${NC}"
        fi
        return 1
    fi
    
    log "INFO" "PARTUUID для DATA раздела: $PARTUUID"
    
    # Обновляем grub.cfg на EFI разделе
    GRUB_CFG="/mnt/efi/boot/grub/grub.cfg"
    
    if [ -f "$GRUB_CFG" ]; then
        # Создаем бэкап
        cp "$GRUB_CFG" "$GRUB_CFG.backup"
        
        # Заменяем PARTUUID
        sed -i "s/PARTUUID=[0-9a-f-]*/PARTUUID=$PARTUUID/g" "$GRUB_CFG"
        
        if [ $? -eq 0 ]; then
            log "INFO" "PARTUUID успешно обновлен в grub.cfg"
            if [ "$LANG" = "ru" ]; then
                echo -e "${GREEN}Конфигурация загрузчика обновлена${NC}"
            else
                echo -e "${GREEN}Bootloader configuration updated${NC}"
            fi
        else
            log "ERROR" "Не удалось обновить grub.cfg"
            if [ "$LANG" = "ru" ]; then
                echo -e "${RED}Не удалось обновить конфигурацию загрузчика${NC}"
            else
                echo -e "${RED}Failed to update bootloader configuration${NC}"
            fi
        fi
    else
        log "WARNING" "grub.cfg не найден: $GRUB_CFG"
        if [ "$LANG" = "ru" ]; then
            echo -e "${YELLOW}grub.cfg не найден, возможно другой загрузчик${NC}"
        else
            echo -e "${YELLOW}grub.cfg not found, possibly different bootloader${NC}"
        fi
    fi
}

# Очистка и финализация
cleanup() {
    log "INFO" "Очистка и финализация"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Очистка...${NC}"
    else
        echo -e "${YELLOW}Cleaning up...${NC}"
    fi
    
    # Размонтирование
    umount /mnt/efi 2>/dev/null
    umount /mnt/data 2>/dev/null
    rmdir /mnt/efi /mnt/data 2>/dev/null
    
    log "INFO" "Очистка завершена"
    
    # Подсчет статистики (приблизительный)
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}Установка завершена!${NC}"
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}ВАЖНО: После перезагрузки выберите новый диск в BIOS/UEFI${NC}"
        echo -e "${YELLOW}Лог установки: $LOG_FILE${NC}"
        echo -e "${GREEN}========================================${NC}\n"
    else
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}Installation completed!${NC}"
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}IMPORTANT: After reboot, select the new disk in BIOS/UEFI${NC}"
        echo -e "${YELLOW}Installation log: $LOG_FILE${NC}"
        echo -e "${GREEN}========================================${NC}\n"
    fi
    
    # Пауза, чтобы пользователь прочитал сообщение
    read -p "$(echo -e "${YELLOW}Press Enter to exit / Нажмите Enter для выхода${NC}")"
}

# ========== ОСНОВНАЯ ЛОГИКА ==========

# Настройка логирования
setup_logging

# Выбор языка
choose_language

# ========== ПРОВЕРКА ИНТЕРНЕТА ==========
if [ "$LANG" = "ru" ]; then
    echo -e "${YELLOW}Проверка подключения к интернету...${NC}"
else
    echo -e "${YELLOW}Checking internet connection...${NC}"
fi

check_internet
INTERNET_STATUS=$?

if [ $INTERNET_STATUS -ne 0 ]; then
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${RED}ОШИБКА: Для работы скрипта необходим доступ в интернет.${NC}"
        echo -e "${YELLOW}Проверены: 1.1.1.1, 9.9.9.9, openwrt.org, kernel.org${NC}"
        echo -e "${YELLOW}Пожалуйста, подключите сетевой кабель и запустите скрипт заново.${NC}\n"
    else
        echo -e "\n${RED}ERROR: Internet connection is required for this script.${NC}"
        echo -e "${YELLOW}Checked: 1.1.1.1, 9.9.9.9, openwrt.org, kernel.org${NC}"
        echo -e "${YELLOW}Please connect network cable and run the script again.${NC}\n"
    fi
    log "ERROR" "Нет подключения к интернету. Скрипт остановлен."
    exit 1
fi

if [ "$LANG" = "ru" ]; then
    echo -e "${GREEN}Интернет доступен. Продолжаем...${NC}\n"
else
    echo -e "${GREEN}Internet is available. Continuing...${NC}\n"
fi

# Установка пакетов
install_packages

# Проверка наличия необходимых команд
check_required_commands

# Выбор целевого диска (куда устанавливать)
select_target_disk

# Поиск исходного диска (откуда копировать)
find_source_disk

# Проверка, что диски разные
check_disks_different

# Создание разделов
create_partitions

# Форматирование
format_partitions

# Монтирование
mount_partitions

# Копирование
copy_system

# Обновление PARTUUID
update_partuuid

# Очистка
cleanup

exit 0