
# Установщик OpenWRT с USB на внутренний диск (x86)
# OpenWRT USB to Internal Disk Installer (x86)

---

## Русский 🇷🇺

### Описание
Скрипт для автоматической установки OpenWRT с USB-флешки на внутренний диск x86 ПК. Скрипт создаёт разделы, форматирует их, копирует систему и обновляет конфигурацию загрузчика.

### Возможности
- 🌍 **Двуязычный интерфейс** (русский/английский) — выбор языка в начале
- 💾 **Автоматическое создание разделов** (sfdisk):
  - GPT таблица разделов
  - EFI раздел (256 МБ, FAT32) с флагом ESP
  - DATA раздел (ext4) на всём оставшемся месте
- 🔄 **Копирование системы** с USB на внутренний диск (rsync или cp)
- ⚙️ **Обновление PARTUUID** в grub.cfg для корректной загрузки
- 📝 **Полное логирование** всех действий
- 🔍 **Просмотр лога при ошибке** (nano/vi/vim/less)
- ✅ **Итоговая статистика** (количество файлов, размер данных)
- ⚠️ **Красное напоминание про BIOS** после установки

### Требования
- ПК с архитектурой x86_64
- OpenWRT установленный на USB-флешке (загрузка с этой флешки)
- Внутренний диск (SSD/HDD) для установки
- Наличие интернета для установки пакетов (опционально)

### Устанавливаемые пакеты
Скрипт автоматически установит (если есть интернет):
- `sfdisk` — создание разделов
- `dosfstools` — форматирование EFI в FAT32
- `blkid` — получение PARTUUID
- `rsync` — быстрое копирование
- `nano` — редактор для просмотра логов

### Использование
1. Загрузите ПК с USB-флешки с OpenWRT
2. Подключитесь по SSH или откройте терминал
3. Скачайте и запустите скрипт:
   ```bash
   wget -O install.sh https://raw.githubusercontent.com/Rever-end/openwrt_usb_installer_x86/main/install.sh
   chmod +x install.sh
   ./install.sh
```

1. Следуйте инструкциям на экране:
   · Выберите язык (1 — русский, 2 — английский)
   · Выберите целевой диск для установки
   · Подтвердите форматирование (yes)
   · Дождитесь завершения копирования
   · Перезагрузитесь и выберите новый диск в BIOS

Логирование

· Все действия сохраняются в /tmp/openwrt_installer/install_ГГГГММДД_ЧЧММСС.log
· При ошибке скрипт предложит открыть лог
· Лог можно посмотреть в любое время командой:
  ```bash
  nano /tmp/openwrt_installer/install_*.log
  ```

Как это работает

1. Проверка системы: определяет версию OpenWRT и менеджер пакетов (apk/opkg)
2. Установка пакетов: обновляет список и устанавливает необходимые утилиты
3. Выбор диска: показывает доступные диски с моделями и размерами (через /sys/block/)
4. Создание разделов с помощью sfdisk:
   · GPT таблица
   · EFI раздел (256 МБ, FAT32) с флагом ESP
   · DATA раздел (ext4) на оставшемся месте
5. Форматирование: FAT32 для EFI, ext4 для DATA
6. Поиск исходного диска: определяет USB-флешку с OpenWRT
7. Копирование: переносит все данные с USB на внутренний диск (rsync или cp)
8. Настройка загрузчика: обновляет PARTUUID в grub.cfg
9. Завершение: показывает статистику и красное напоминание про BIOS

История изменений

· v2.0 — Полный переход на sfdisk, добавлено логирование, nano в комплекте
· v1.0 — Первая версия с parted

Лицензия

MIT License. Подробнее в файле LICENSE.

Автор

Rever-end

---

English 🇬🇧

Description

A script for automatic installation of OpenWRT from a USB flash drive to an internal x86 PC disk. The script creates partitions, formats them, copies the system, and updates the bootloader configuration.

Features

· 🌍 Bilingual interface (Russian/English) — language selection at start
· 💾 Automatic partition creation (sfdisk):
  · GPT partition table
  · EFI partition (256 MB, FAT32) with ESP flag
  · DATA partition (ext4) on all remaining space
· 🔄 System copying from USB to internal disk (rsync or cp)
· ⚙️ PARTUUID update in grub.cfg for correct booting
· 📝 Full logging of all actions
· 🔍 Log viewer on error (nano/vi/vim/less)
· ✅ Final statistics (file count, data size)
· ⚠️ Red-colored BIOS reminder after installation

Requirements

· x86_64 PC architecture
· OpenWRT installed on a USB flash drive (booting from this USB)
· Internal disk (SSD/HDD) for installation
· Internet connection for package installation (optional)

Installed Packages

The script will automatically install (if internet available):

· sfdisk — partition creation
· dosfstools — EFI FAT32 formatting
· blkid — PARTUUID retrieval
· rsync — fast copying
· nano — log viewer editor

Usage

1. Boot your PC from the OpenWRT USB flash drive
2. Connect via SSH or open terminal
3. Download and run the script:
   ```bash
   wget -O install.sh https://raw.githubusercontent.com/Rever-end/openwrt_usb_installer_x86/main/install.sh
   chmod +x install.sh
   ./install.sh
   ```
4. Follow the on-screen instructions:
   · Select language (1 — Russian, 2 — English)
   · Select target disk for installation
   · Confirm formatting (yes)
   · Wait for copying to complete
   · Reboot and select new disk in BIOS

Logging

· All actions saved to /tmp/openwrt_installer/install_YYYYMMDD_HHMMSS.log
· On error, script will ask to open the log
· Log can be viewed anytime with:
  ```bash
  nano /tmp/openwrt_installer/install_*.log
  ```

How it works

1. System check: detects OpenWRT version and package manager (apk/opkg)
2. Package installation: updates package list and installs required tools
3. Disk selection: shows available disks with models and sizes (via /sys/block/)
4. Partition creation with sfdisk:
   · GPT table
   · EFI partition (256 MB, FAT32) with ESP flag
   · DATA partition (ext4) on remaining space
5. Formatting: FAT32 for EFI, ext4 for DATA
6. Source disk detection: finds the USB flash drive with OpenWRT
7. Copying: transfers all data from USB to internal disk (rsync or cp)
8. Bootloader configuration: updates PARTUUID in grub.cfg
9. Completion: shows statistics and red BIOS reminder

Changelog

· v2.0 — Full migration to sfdisk, logging added, nano included
· v1.0 — First version with parted

License

MIT License. See LICENSE file for details.

Author

Rever-end
