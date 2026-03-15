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
BOLD='\033[1m'      # Жирный текст
NC='\033[0m' # No Color

# ========== ОБРАБОТКА ПРЕРЫВАНИЙ ==========
cleanup_on_exit() {
    echo -e "\n${YELLOW}Прерывание! Выполняю очистку...${NC}"
    umount /mnt/efi 2>/dev/null
    umount /mnt/data 2>/dev/null
    umount /mnt/source_boot 2>/dev/null
    umount /mnt/source_data 2>/dev/null
    umount /mnt/scan_disk 2>/dev/null
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
    PACKAGES="sfdisk dosfstools rsync blkid nano parted mount-utils"
    
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

# ========== УЛУЧШЕННЫЙ ПОИСК ИСХОДНОГО ДИСКА ПО СОДЕРЖИМОМУ ==========
find_source_disk() {
    log "INFO" "Поиск исходного диска с OpenWRT по содержимому"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${YELLOW}=== ПОИСК ИСХОДНОГО ДИСКА С OpenWRT ===${NC}"
        echo -e "${YELLOW}Сканирую диски в поисках файлов OpenWRT...${NC}\n"
    else
        echo -e "\n${YELLOW}=== LOOKING FOR SOURCE DISK WITH OpenWRT ===${NC}"
        echo -e "${YELLOW}Scanning disks for OpenWRT files...${NC}\n"
    fi
    
    # Создаём временную директорию для монтирования
    mkdir -p /mnt/scan_disk
    
    SOURCE_DISK=""
    FOUND_COUNT=0
    FOUND_DISKS=""
    FIRST_FOUND=""
    FIRST_MODEL=""
    
    # Перебираем все диски
    for disk in /sys/block/*; do
        disk_name=$(basename "$disk")
        # Пропускаем loop-устройства и RAM-диски
        case "$disk_name" in
            loop*|ram*|sr*) continue ;;
        esac
        
        disk_dev="/dev/$disk_name"
        
        # Пропускаем целевой диск, если он уже выбран
        if [ -n "$TARGET_DISK" ] && [ "$disk_dev" = "$TARGET_DISK" ]; then
            log "INFO" "Пропускаем целевой диск: $disk_dev"
            continue
        fi
        
        # Получаем модель диска для красивого вывода
        model=""
        if [ -f "$disk/device/model" ]; then
            model=$(cat "$disk/device/model")
        fi
        
        # Перебираем все разделы диска (до 8)
        for part_num in 1 2 3 4 5 6 7 8; do
            part_dev="${disk_dev}${part_num}"
            
            if [ ! -b "$part_dev" ]; then
                continue
            fi
            
            log "INFO" "Проверка $part_dev на наличие OpenWRT"
            
            # Пробуем примонтировать
            if mount "$part_dev" /mnt/scan_disk 2>/dev/null; then
                
                FOUND=0
                REASON=""
                
                # ========== ПРОВЕРКА ПРИЗНАКОВ OPENWRT ==========
                
                # Основной признак - openwrt_release
                if [ -f "/mnt/scan_disk/etc/openwrt_release" ]; then
                    FOUND=1
                    REASON="openwrt_release"
                
                # Файл os-release с ID=openwrt
                elif [ -f "/mnt/scan_disk/etc/os-release" ] && grep -q "^ID=openwrt" "/mnt/scan_disk/etc/os-release" 2>/dev/null; then
                    FOUND=1
                    REASON="os-release (ID=openwrt)"
                
                # Файл os-release с NAME=OpenWrt
                elif [ -f "/mnt/scan_disk/etc/os-release" ] && grep -q "^NAME=.*OpenWrt" "/mnt/scan_disk/etc/os-release" 2>/dev/null; then
                    FOUND=1
                    REASON="os-release (NAME=OpenWrt)"
                
                # Файл banner с текстом OpenWrt
                elif [ -f "/mnt/scan_disk/etc/banner" ] && grep -q "OpenWrt" "/mnt/scan_disk/etc/banner" 2>/dev/null; then
                    FOUND=1
                    REASON="banner (OpenWrt)"
                
                # Новый пакетный менеджер apk
                elif [ -d "/mnt/scan_disk/etc/apk" ]; then
                    FOUND=1
                    REASON="apk directory"
                
                # Старый пакетный менеджер opkg
                elif [ -d "/mnt/scan_disk/etc/opkg" ]; then
                    FOUND=1
                    REASON="opkg directory"
                
                # Старая версия opkg в lib
                elif [ -d "/mnt/scan_disk/lib/opkg" ]; then
                    FOUND=1
                    REASON="lib/opkg directory"
                
                # Файл version с текстом OpenWrt
                elif [ -f "/mnt/scan_disk/etc/version" ] && grep -q "OpenWrt" "/mnt/scan_disk/etc/version" 2>/dev/null; then
                    FOUND=1
                    REASON="version file"
                
                # Директория /rom (характерно для OpenWRT)
                elif [ -d "/mnt/scan_disk/rom" ]; then
                    FOUND=1
                    REASON="/rom directory"
                
                # Наличие busybox (запасной вариант)
                elif [ -f "/mnt/scan_disk/bin/busybox" ]; then
                    # Дополнительная проверка: если нет признаков других дистрибутивов
                    if [ ! -f "/mnt/scan_disk/etc/debian_version" ] && \
                       [ ! -f "/mnt/scan_disk/etc/redhat-release" ] && \
                       [ ! -f "/mnt/scan_disk/etc/arch-release" ]; then
                        FOUND=1
                        REASON="busybox (embedded)"
                    fi
                fi
                # ========== КОНЕЦ ПРОВЕРКИ ==========
                
                umount /mnt/scan_disk
                
                if [ $FOUND -eq 1 ]; then
                    FOUND_COUNT=$((FOUND_COUNT + 1))
                    FOUND_DISKS="$FOUND_DISKS $disk_dev"
                    
                    # Запоминаем первый найденный диск (для случая одного диска)
                    if [ $FOUND_COUNT -eq 1 ]; then
                        FIRST_FOUND="$disk_dev"
                        FIRST_MODEL="$model"
                    fi
                    
                    # Переходим к следующему диску (не проверяем остальные разделы)
                    break
                fi
            fi
        done
    done
    
    # Удаляем временную директорию
    rmdir /mnt/scan_disk 2>/dev/null
    
    echo ""
    
    # Анализируем результаты
    if [ $FOUND_COUNT -eq 0 ]; then
        # Если не нашли ни одного диска с OpenWRT
        log "ERROR" "Не найдено ни одного диска с OpenWRT"
        
        if [ "$LANG" = "ru" ]; then
            echo -e "\n${RED}ОШИБКА: Не найдено ни одного диска с OpenWRT!${NC}"
            echo -e "${YELLOW}Убедитесь, что вы загрузились с USB-флешки с OpenWRT${NC}"
            echo -e "${YELLOW}Доступные диски:${NC}\n"
        else
            echo -e "\n${RED}ERROR: No OpenWRT disks found!${NC}"
            echo -e "${YELLOW}Make sure you booted from OpenWRT USB flash drive${NC}"
            echo -e "${YELLOW}Available disks:${NC}\n"
        fi
        
        # Показываем все диски для ручного выбора
        SOURCE_COUNT=0
        SOURCE_DISKS=""
        
        for disk in /sys/block/*; do
            disk_name=$(basename "$disk")
            case "$disk_name" in
                loop*|ram*|sr*) continue ;;
            esac
            
            disk_dev="/dev/$disk_name"
            
            # Пропускаем целевой диск
            if [ -n "$TARGET_DISK" ] && [ "$disk_dev" = "$TARGET_DISK" ]; then
                continue
            fi
            
            # Получаем размер и модель
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
            
            model=""
            if [ -f "$disk/device/model" ]; then
                model=$(cat "$disk/device/model")
            fi
            
            SOURCE_COUNT=$((SOURCE_COUNT + 1))
            SOURCE_DISKS="$SOURCE_DISKS $disk_dev"
            
            echo "$SOURCE_COUNT) $disk_dev - $model ($size_human)"
        done
        
        if [ $SOURCE_COUNT -eq 0 ]; then
            error_exit "No disks available / Нет доступных дисков"
        fi
        
        if [ $SOURCE_COUNT -eq 1 ]; then
            # Если только один вариант
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
                echo -e "${GREEN}Выбран исходный диск: $SOURCE_DISK${NC}\n"
            else
                error_exit "Operation cancelled / Операция отменена"
            fi
        else
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
            echo -e "${GREEN}Выбран исходный диск: $SOURCE_DISK${NC}\n"
        fi
        
    elif [ $FOUND_COUNT -eq 1 ]; then
        # Нашли ровно один диск с OpenWRT
        SOURCE_DISK="$FIRST_FOUND"
        if [ "$LANG" = "ru" ]; then
            echo -e "${GREEN}Найден диск с OpenWRT: $SOURCE_DISK $FIRST_MODEL${NC}"
            read -p "$(echo -e "${YELLOW}Копировать систему с этого диска? (Y/n): ${NC}")" SOURCE_CONFIRM
        else
            echo -e "${GREEN}Found OpenWRT disk: $SOURCE_DISK $FIRST_MODEL${NC}"
            read -p "$(echo -e "${YELLOW}Copy system from this disk? (Y/n): ${NC}")" SOURCE_CONFIRM
        fi
        
        if [ -z "$SOURCE_CONFIRM" ] || [ "$SOURCE_CONFIRM" = "y" ] || [ "$SOURCE_CONFIRM" = "Y" ]; then
            log "INFO" "Исходный диск подтверждён: $SOURCE_DISK"
            echo -e "${GREEN}Исходный диск: $SOURCE_DISK${NC}\n"
        else
            error_exit "Operation cancelled / Операция отменена"
        fi
        
    else
        # Нашли несколько дисков с OpenWRT
        if [ "$LANG" = "ru" ]; then
            echo -e "\n${YELLOW}Найдено несколько дисков с OpenWRT:${NC}"
            echo -e "${YELLOW}Выберите нужный:${NC}\n"
        else
            echo -e "\n${YELLOW}Found multiple OpenWRT disks:${NC}"
            echo -e "${YELLOW}Select the correct one:${NC}\n"
        fi
        
        # Выводим список найденных дисков
        DISK_NUM=1
        for disk in $FOUND_DISKS; do
            disk_name=$(basename "$disk")
            model=""
            if [ -f "/sys/block/$disk_name/device/model" ]; then
                model=$(cat "/sys/block/$disk_name/device/model")
            fi
            echo "$DISK_NUM) $disk - $model"
            DISK_NUM=$((DISK_NUM + 1))
        done
        
        read -p "$(echo -e "${YELLOW}Enter number / Введите номер: ${NC}")" SOURCE_NUM
        
        if ! echo "$SOURCE_NUM" | grep -qE '^[0-9]+$' || [ "$SOURCE_NUM" -lt 1 ] || [ "$SOURCE_NUM" -gt "$FOUND_COUNT" ]; then
            error_exit "Invalid number / Неверный номер"
        fi
        
        SOURCE_DISK=$(echo $FOUND_DISKS | tr ' ' '\n' | sed -n "${SOURCE_NUM}p")
        log "INFO" "Исходный диск выбран из нескольких: $SOURCE_DISK"
        echo -e "${GREEN}Выбран исходный диск: $SOURCE_DISK${NC}\n"
    fi
}

# ========== ПРОВЕРКА, ЧТО ДИСКИ РАЗНЫЕ ==========
check_disks_different() {
    if [ "$TARGET_DISK" = "$SOURCE_DISK" ]; then
        error_exit "Target disk is the same as source disk! / Целевой диск совпадает с исходным!"
    fi
}

# ========== РАЗМОНТИРОВАНИЕ ЦЕЛЕВОГО ДИСКА ==========
unmount_target_disk() {
    log "INFO" "Проверка и размонтирование разделов на $TARGET_DISK"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Проверка и размонтирование разделов целевого диска...${NC}"
    else
        echo -e "${YELLOW}Checking and unmounting target disk partitions...${NC}"
    fi
    
    # Размонтируем все разделы целевого диска
    for part in $(ls ${TARGET_DISK}* 2>/dev/null); do
        if mount | grep -q "$part"; then
            log "INFO" "Размонтирование $part"
            umount "$part" >> "$LOG_FILE" 2>&1
            sleep 1
        fi
    done
    
    # Отключаем swap на целевом диске
    for part in $(ls ${TARGET_DISK}* 2>/dev/null); do
        if swapon -s 2>/dev/null | grep -q "$part"; then
            log "INFO" "Отключение swap на $part"
            swapoff "$part" >> "$LOG_FILE" 2>&1
        fi
    done
    
    # Даем системе время на освобождение
    sleep 2
    log "INFO" "Размонтирование целевого диска завершено"
}

# Создание разделов на целевом диске
create_partitions() {
    log "INFO" "Создание разделов на $TARGET_DISK"
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${YELLOW}Создание разделов на $TARGET_DISK...${NC}"
    else
        echo -e "${YELLOW}Creating partitions on $TARGET_DISK...${NC}"
    fi
    
    # Сначала размонтируем целевой диск
    unmount_target_disk
    
    # Очистка существующей таблицы разделов и создание GPT
    log "INFO" "Очистка диска и создание GPT таблицы"
    dd if=/dev/zero of="$TARGET_DISK" bs=1M count=1 >> "$LOG_FILE" 2>&1
    
    # Создание разделов через sfdisk с флагом --force
    log "INFO" "Создание разделов через sfdisk"
    echo "label: gpt" | sfdisk --force "$TARGET_DISK" >> "$LOG_FILE" 2>&1
    
    # Создание EFI раздела (256 MB) с правильным типом для UEFI
    echo "size=256M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=\"EFI\"" | sfdisk --force -a "$TARGET_DISK" >> "$LOG_FILE" 2>&1
    
    # Создание DATA раздела на остатке
    echo "type=L, name=\"DATA\"" | sfdisk --force -a "$TARGET_DISK" >> "$LOG_FILE" 2>&1
    
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
    echo -e "${YELLOW}Форматирование EFI раздела в FAT32...${NC}"
    $FAT_CMD -F32 -n "EFI" "$EFI_PART" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        error_exit "Failed to format EFI partition / Не удалось отформатировать EFI раздел"
    fi
    
    # Установка флага ESP
    if command -v parted >/dev/null 2>&1; then
        log "INFO" "Установка флага esp on через parted"
        echo -e "${YELLOW}Устанавливаем флаг ESP (EFI System Partition) для загрузки в UEFI...${NC}"
        parted "$TARGET_DISK" set 1 esp on >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Флаг ESP успешно установлен${NC}"
        fi
    fi
    
    # Форматирование DATA в ext4
    log "INFO" "Форматирование $DATA_PART в ext4"
    echo -e "${YELLOW}Форматирование DATA раздела в ext4...${NC}"
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

# ========== УНИВЕРСАЛЬНАЯ ФУНКЦИЯ ПРОВЕРКИ МОНТИРОВАНИЯ ==========
is_mounted() {
    local dir="$1"
    
    # Если есть команда mountpoint - используем её
    if command -v mountpoint >/dev/null 2>&1; then
        mountpoint -q "$dir" 2>/dev/null
        return $?
    fi
    
    # Если нет mountpoint - проверяем через /proc/mounts
    if grep -q " $dir " /proc/mounts 2>/dev/null; then
        return 0
    else
        return 1
    fi
}
# ========== КОНЕЦ УНИВЕРСАЛЬНОЙ ФУНКЦИИ ==========

# ========== ФУНКЦИЯ КОНВЕРТАЦИИ РАЗМЕРА ==========
format_size() {
    local bytes="$1"
    
    if [ -z "$bytes" ] || [ "$bytes" -eq 0 ]; then
        echo "0B"
        return
    fi
    
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec "$bytes" 2>/dev/null || echo "${bytes}B"
    else
        # Ручное форматирование
        if [ "$bytes" -gt 1073741824 ]; then
            echo "$((bytes / 1073741824))G"
        elif [ "$bytes" -gt 1048576 ]; then
            echo "$((bytes / 1048576))M"
        elif [ "$bytes" -gt 1024 ]; then
            echo "$((bytes / 1024))K"
        else
            echo "${bytes}B"
        fi
    fi
}
# ========== КОНЕЦ ФУНКЦИИ КОНВЕРТАЦИИ ==========

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
    
    # Создаем точки монтирования
    mkdir -p /mnt/source_boot /mnt/source_data
    
    # Проверяем, не примонтированы ли уже разделы
    BOOT_MOUNTED=0
    DATA_MOUNTED=0
    
    if is_mounted "/mnt/source_boot"; then
        log "INFO" "Boot раздел уже примонтирован в /mnt/source_boot"
        BOOT_MOUNTED=1
    else
        log "INFO" "Монтирование $SOURCE_BOOT в /mnt/source_boot"
        mount "$SOURCE_BOOT" /mnt/source_boot >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            error_exit "Failed to mount source boot partition / Не удалось примонтировать исходный boot раздел"
        fi
    fi
    
    if is_mounted "/mnt/source_data"; then
        log "INFO" "Data раздел уже примонтирован в /mnt/source_data"
        DATA_MOUNTED=1
    else
        log "INFO" "Монтирование $SOURCE_DATA в /mnt/source_data"
        mount "$SOURCE_DATA" /mnt/source_data >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            if [ $BOOT_MOUNTED -eq 0 ]; then
                umount /mnt/source_boot 2>/dev/null
            fi
            error_exit "Failed to mount source data partition / Не удалось примонтировать исходный data раздел"
        fi
    fi
    
    # ========== ПРОВЕРКА РАЗМЕРОВ ==========
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${YELLOW}Проверка размеров разделов...${NC}"
    else
        echo -e "\n${YELLOW}Checking partition sizes...${NC}"
    fi
    
    # Получаем размер исходных данных в байтах
    BOOT_SIZE_BYTES=$(du -sb /mnt/source_boot 2>/dev/null | cut -f1)
    DATA_SIZE_BYTES=$(du -sb /mnt/source_data 2>/dev/null | cut -f1)
    
    # Получаем размер целевых разделов в байтах
    EFI_SIZE_BYTES=$(df -B1 /mnt/efi 2>/dev/null | awk 'NR==2 {print $2}')
    DATA_TARGET_SIZE_BYTES=$(df -B1 /mnt/data 2>/dev/null | awk 'NR==2 {print $2}')
    
    # Конвертируем в человеко-читаемый формат
    BOOT_SIZE_HUMAN=$(format_size "$BOOT_SIZE_BYTES")
    DATA_SIZE_HUMAN=$(format_size "$DATA_SIZE_BYTES")
    EFI_SIZE_HUMAN=$(format_size "$EFI_SIZE_BYTES")
    DATA_TARGET_SIZE_HUMAN=$(format_size "$DATA_TARGET_SIZE_BYTES")
    
    # Проверка boot раздела
    if [ -n "$BOOT_SIZE_BYTES" ] && [ -n "$EFI_SIZE_BYTES" ] && [ "$BOOT_SIZE_BYTES" -gt "$EFI_SIZE_BYTES" ]; then
        log "ERROR" "Boot раздел слишком большой: $BOOT_SIZE_BYTES > $EFI_SIZE_BYTES"
        if [ "$LANG" = "ru" ]; then
            echo -e "\n${RED}========================================${NC}"
            echo -e "${RED}ОШИБКА: Недостаточно места на целевом диске!${NC}"
            echo -e "${RED}========================================${NC}"
            echo -e "${YELLOW}Boot раздел (исходный): ${BOOT_SIZE_HUMAN}${NC}"
            echo -e "${YELLOW}EFI раздел (целевой):  ${EFI_SIZE_HUMAN}${NC}"
            echo -e "${RED}Исходный boot раздел больше целевого EFI раздела.${NC}"
            echo -e "${YELLOW}Увеличьте размер EFI раздела или используйте диск большего объёма.${NC}"
        else
            echo -e "\n${RED}========================================${NC}"
            echo -e "${RED}ERROR: Not enough space on target disk!${NC}"
            echo -e "${RED}========================================${NC}"
            echo -e "${YELLOW}Boot partition (source): ${BOOT_SIZE_HUMAN}${NC}"
            echo -e "${YELLOW}EFI partition (target):  ${EFI_SIZE_HUMAN}${NC}"
            echo -e "${RED}Source boot partition is larger than target EFI partition.${NC}"
            echo -e "${YELLOW}Increase EFI partition size or use larger disk.${NC}"
        fi
        error_exit "Source boot partition too large / Исходный boot раздел слишком большой"
    fi
    
    # Проверка data раздела
    if [ -n "$DATA_SIZE_BYTES" ] && [ -n "$DATA_TARGET_SIZE_BYTES" ] && [ "$DATA_SIZE_BYTES" -gt "$DATA_TARGET_SIZE_BYTES" ]; then
        log "ERROR" "Data раздел слишком большой: $DATA_SIZE_BYTES > $DATA_TARGET_SIZE_BYTES"
        if [ "$LANG" = "ru" ]; then
            echo -e "\n${RED}========================================${NC}"
            echo -e "${RED}ОШИБКА: Недостаточно места на целевом диске!${NC}"
            echo -e "${RED}========================================${NC}"
            echo -e "${YELLOW}Data раздел (исходный): ${DATA_SIZE_HUMAN}${NC}"
            echo -e "${YELLOW}DATA раздел (целевой):  ${DATA_TARGET_SIZE_HUMAN}${NC}"
            echo -e "${RED}Исходный data раздел больше целевого DATA раздела.${NC}"
            echo -e "${YELLOW}Используйте диск большего объёма.${NC}"
        else
            echo -e "\n${RED}========================================${NC}"
            echo -e "${RED}ERROR: Not enough space on target disk!${NC}"
            echo -e "${RED}========================================${NC}"
            echo -e "${YELLOW}Data partition (source): ${DATA_SIZE_HUMAN}${NC}"
            echo -e "${YELLOW}DATA partition (target): ${DATA_TARGET_SIZE_HUMAN}${NC}"
            echo -e "${RED}Source data partition is larger than target DATA partition.${NC}"
            echo -e "${YELLOW}Use larger disk.${NC}"
        fi
        error_exit "Source data partition too large / Исходный data раздел слишком большой"
    fi
    
    if [ "$LANG" = "ru" ]; then
        echo -e "${GREEN}✓ Размеры подходят для копирования${NC}\n"
    else
        echo -e "${GREEN}✓ Sizes are OK for copying${NC}\n"
    fi
    # ========== КОНЕЦ ПРОВЕРКИ РАЗМЕРОВ ==========
    
    # Копирование boot раздела
    log "INFO" "Копирование boot раздела"
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${YELLOW}Копирование boot раздела...${NC}"
    else
        echo -e "\n${YELLOW}Copying boot partition...${NC}"
    fi
    
    # Временный файл для вывода rsync
    TEMP_RSYNC_OUT="/tmp/rsync_out.$$"
    
    if command -v rsync >/dev/null 2>&1; then
        # Проверяем версию rsync
        RSYNC_VERSION=$(rsync --version 2>/dev/null | head -1)
        log "INFO" "Найден rsync: $RSYNC_VERSION"
        
        # Пробуем скопировать через rsync
        rsync -a /mnt/source_boot/ /mnt/efi/ > "$TEMP_RSYNC_OUT" 2>&1
        RSYNC_EXIT=$?
        
        if [ $RSYNC_EXIT -eq 0 ]; then
            # Успешно
            TOTAL_SIZE=$(grep "total size is" "$TEMP_RSYNC_OUT" 2>/dev/null | tail -1 | awk '{print $4}')
            if [ -n "$TOTAL_SIZE" ] && [ "$TOTAL_SIZE" != "0" ]; then
                SIZE_HUMAN=$(format_size "$TOTAL_SIZE")
                if [ "$LANG" = "ru" ]; then
                    echo -e "${GREEN}✓ Копирование boot раздела завершено (${SIZE_HUMAN})${NC}"
                else
                    echo -e "${GREEN}✓ Boot partition copy completed (${SIZE_HUMAN})${NC}"
                fi
                log "INFO" "Boot раздел успешно скопирован через rsync, размер: $TOTAL_SIZE байт ($SIZE_HUMAN)"
            else
                if [ "$LANG" = "ru" ]; then
                    echo -e "${GREEN}✓ Копирование boot раздела завершено${NC}"
                else
                    echo -e "${GREEN}✓ Boot partition copy completed${NC}"
                fi
                log "INFO" "Boot раздел успешно скопирован через rsync (размер не определён)"
            fi
        else
            # Ошибка rsync - логируем причину и падаем в cp
            log "WARNING" "rsync завершился с ошибкой (код: $RSYNC_EXIT)"
            
            # Парсим ошибку из вывода
            RSYNC_ERROR=$(grep -i "error\|failed\|cannot" "$TEMP_RSYNC_OUT" 2>/dev/null | head -3 | tr '\n' '; ')
            if [ -n "$RSYNC_ERROR" ]; then
                log "WARNING" "Ошибка rsync: $RSYNC_ERROR"
            else
                log "WARNING" "Полный вывод rsync сохранён в логе"
                cat "$TEMP_RSYNC_OUT" >> "$LOG_FILE" 2>&1
            fi
            
            # Пробуем через cp как запасной вариант
            log "INFO" "Пробуем скопировать через cp (как запасной вариант)"
            cp -a /mnt/source_boot/. /mnt/efi/ >> "$LOG_FILE" 2>&1
            if [ $? -eq 0 ]; then
                if [ "$LANG" = "ru" ]; then
                    echo -e "${GREEN}✓ Копирование boot раздела завершено${NC}"
                else
                    echo -e "${GREEN}✓ Boot partition copy completed${NC}"
                fi
                log "INFO" "Boot раздел скопирован через cp (rsync не сработал)"
            else
                log "ERROR" "Ошибка при копировании boot раздела через cp"
                error_exit "Failed to copy boot partition / Не удалось скопировать boot раздел"
            fi
        fi
        rm -f "$TEMP_RSYNC_OUT"
    else
        # rsync не найден в системе
        log "INFO" "rsync не установлен в системе, используется cp"
        cp -a /mnt/source_boot/. /mnt/efi/ >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            if [ "$LANG" = "ru" ]; then
                echo -e "${GREEN}✓ Копирование boot раздела завершено${NC}"
            else
                echo -e "${GREEN}✓ Boot partition copy completed${NC}"
            fi
            log "INFO" "Boot раздел скопирован через cp (rsync отсутствует)"
        else
            log "ERROR" "Ошибка при копировании boot раздела через cp"
            error_exit "Failed to copy boot partition / Не удалось скопировать boot раздел"
        fi
    fi
    
    # Копирование data раздела
    log "INFO" "Копирование data раздела"
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${YELLOW}Копирование data раздела...${NC}"
    else
        echo -e "\n${YELLOW}Copying data partition...${NC}"
    fi
    
    if command -v rsync >/dev/null 2>&1; then
        # Проверяем версию rsync
        RSYNC_VERSION=$(rsync --version 2>/dev/null | head -1)
        log "INFO" "Найден rsync: $RSYNC_VERSION"
        
        rsync -a /mnt/source_data/ /mnt/data/ > "$TEMP_RSYNC_OUT" 2>&1
        RSYNC_EXIT=$?
        
        if [ $RSYNC_EXIT -eq 0 ]; then
            TOTAL_SIZE=$(grep "total size is" "$TEMP_RSYNC_OUT" 2>/dev/null | tail -1 | awk '{print $4}')
            if [ -n "$TOTAL_SIZE" ] && [ "$TOTAL_SIZE" != "0" ]; then
                SIZE_HUMAN=$(format_size "$TOTAL_SIZE")
                if [ "$LANG" = "ru" ]; then
                    echo -e "${GREEN}✓ Копирование data раздела завершено (${SIZE_HUMAN})${NC}"
                else
                    echo -e "${GREEN}✓ Data partition copy completed (${SIZE_HUMAN})${NC}"
                fi
                log "INFO" "Data раздел успешно скопирован через rsync, размер: $TOTAL_SIZE байт ($SIZE_HUMAN)"
            else
                if [ "$LANG" = "ru" ]; then
                    echo -e "${GREEN}✓ Копирование data раздела завершено${NC}"
                else
                    echo -e "${GREEN}✓ Data partition copy completed${NC}"
                fi
                log "INFO" "Data раздел успешно скопирован через rsync (размер не определён)"
            fi
        else
            log "WARNING" "rsync завершился с ошибкой (код: $RSYNC_EXIT)"
            
            RSYNC_ERROR=$(grep -i "error\|failed\|cannot" "$TEMP_RSYNC_OUT" 2>/dev/null | head -3 | tr '\n' '; ')
            if [ -n "$RSYNC_ERROR" ]; then
                log "WARNING" "Ошибка rsync: $RSYNC_ERROR"
            else
                log "WARNING" "Полный вывод rsync сохранён в логе"
                cat "$TEMP_RSYNC_OUT" >> "$LOG_FILE" 2>&1
            fi
            
            log "INFO" "Пробуем скопировать через cp (как запасной вариант)"
            cp -a /mnt/source_data/. /mnt/data/ >> "$LOG_FILE" 2>&1
            if [ $? -eq 0 ]; then
                if [ "$LANG" = "ru" ]; then
                    echo -e "${GREEN}✓ Копирование data раздела завершено${NC}"
                else
                    echo -e "${GREEN}✓ Data partition copy completed${NC}"
                fi
                log "INFO" "Data раздел скопирован через cp (rsync не сработал)"
            else
                log "ERROR" "Ошибка при копировании data раздела через cp"
                error_exit "Failed to copy data partition / Не удалось скопировать data раздел"
            fi
        fi
        rm -f "$TEMP_RSYNC_OUT"
    else
        log "INFO" "rsync не установлен в системе, используется cp"
        cp -a /mnt/source_data/. /mnt/data/ >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            if [ "$LANG" = "ru" ]; then
                echo -e "${GREEN}✓ Копирование data раздела завершено${NC}"
            else
                echo -e "${GREEN}✓ Data partition copy completed${NC}"
            fi
            log "INFO" "Data раздел скопирован через cp (rsync отсутствует)"
        else
            log "ERROR" "Ошибка при копировании data раздела через cp"
            error_exit "Failed to copy data partition / Не удалось скопировать data раздел"
        fi
    fi
    
    log "INFO" "Копирование завершено"
    
    # Размонтирование исходных разделов
    if [ $BOOT_MOUNTED -eq 0 ]; then
        umount /mnt/source_boot 2>/dev/null
    fi
    if [ $DATA_MOUNTED -eq 0 ]; then
        umount /mnt/source_data 2>/dev/null
    fi
    
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
    
    # Запускаем спиннер
    {
        local spin='-\|/'
        local i=0
        
        while kill -0 $$ 2>/dev/null; do
            i=$(( (i+1) % 4 ))
            printf "\r${YELLOW}Очистка... ${spin:$i:1}${NC}"
            sleep 0.5
        done
    } &
    SPINNER_PID=$!
    
    # Сохраняем время начала
    START_TIME=$(date +%s)
    
    # Размонтирование
    umount /mnt/efi 2>/dev/null
    umount /mnt/data 2>/dev/null
    rmdir /mnt/efi /mnt/data 2>/dev/null
    
    # Считаем время
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Убиваем спиннер
    kill $SPINNER_PID 2>/dev/null
    wait $SPINNER_PID 2>/dev/null
    
    log "INFO" "Очистка завершена за $DURATION секунд"
    
    # Финальное сообщение с временем
    if [ "$LANG" = "ru" ]; then
        echo -e "\r${GREEN}✓ Очистка завершена (${DURATION} сек)${NC}"
    else
        echo -e "\r${GREEN}✓ Cleanup completed (${DURATION} sec)${NC}"
    fi
    
    # Подсчет статистики (приблизительный)
    if [ "$LANG" = "ru" ]; then
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}Установка завершена!${NC}"
        echo -e "${RED}========================================${NC}"
        # Жирный текст и ПОЛНОСТЬЮ КАПС для важного сообщения
        echo -e "${RED}${BOLD}ВАЖНО: ПОСЛЕ ПЕРЕЗАГРУЗКИ ВЫБЕРИТЕ НОВЫЙ ДИСК В BOOT MENU BIOS/UEFI${NC}"
        echo -e ""
        echo -e "${YELLOW}Для входа в Boot Menu обычно используются клавиши:${NC}"
        echo -e "  ${BOLD}F2, F8, F10, F11, F12, Del, Esc${NC}"
        echo -e "${YELLOW}Нажмите нужную клавишу сразу после включения питания${NC}"
        echo -e ""
        echo -e "${YELLOW}Лог установки: $LOG_FILE${NC}"
        echo -e "${GREEN}========================================${NC}\n"
    else
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}Installation completed!${NC}"
        echo -e "${RED}========================================${NC}"
        # Жирный текст и ПОЛНОСТЬЮ КАПС для важного сообщения
        echo -e "${RED}${BOLD}IMPORTANT: AFTER REBOOT, SELECT THE NEW DISK IN BOOT MENU BIOS/UEFI${NC}"
        echo -e ""
        echo -e "${YELLOW}Common keys to enter Boot Menu:${NC}"
        echo -e "  ${BOLD}F2, F8, F10, F11, F12, Del, Esc${NC}"
        echo -e "${YELLOW}Press the appropriate key immediately after power on${NC}"
        echo -e ""
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

# Создание разделов (с автоматическим размонтированием)
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