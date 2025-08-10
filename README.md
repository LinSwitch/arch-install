# LinSwitch 🐧  

**Автоматическая установка Arch Linux на старое железо — без боли.**  
> 💡 Windows 11 не встала? Microsoft требует новое железо?  
> Поставь Arch за 10 минут и продли жизнь ПК ещё на 5 лет!

---
## ⚙️ Что делает скрипт
- **Форматирует диск** → **ставит Arch** → **включает сеть**
- **LUKS2** (шифрование) + **Btrfs** (снапшоты) или **Ext4**
- **Готовые subvolumes** и **загрузчик** (GRUB / systemd-boot)
- **Новый пользователь**, **sudo**, **RU/EN локаль** — «из коробки»


Подходит для установки как на реальное железо, так и в виртуальную машину.
GUI по умолчанию не устанавливается — вы получаете чистую, минималистичную систему.

---
## 📂 Сценарии установки

| Возможность                      | 01 | 02 | 03 | 04 |
|----------------------------------|:--:|:--:|:--:|:--:|
| **Ext4**                         | ✅ | ❌ | ❌ | ❌ |
| **Btrfs + subvolumes**           | ❌ | ✅ | ✅ | ✅ |
| **LUKS2-шифрование**             | ❌ | ❌ | ✅ | ✅ |
| **GRUB**                         | ✅ | ✅ | ✅ | ❌ |
| **systemd-boot**                 | ❌ | ❌ | ❌ | ✅ |
| **Сетевой старт** (NetworkManager) | ✅ | ✅ | ✅ | ✅ |
| **RU/EN локаль**                 | ✅ | ✅ | ✅ | ✅ |
| **Subvol-структура** `@ @home @snapshots …` | ❌ | ✅ | ✅ | ✅ |
> ✅ — включено, ❌ — не используется.


| Сценарий              | Файл                      | Особенности                  |
|-----------------------|---------------------------|------------------------------|
| **Просто работает**   | [01-ext4-grub.sh](https://raw.githubusercontent.com/LinSwitch/install/main/01-ext4-grub.sh)        | ext4, GRUB, swap-файл        |
| **Снимки + откат**    | [02-btrfs-grub.sh](https://raw.githubusercontent.com/LinSwitch/install/main/02-btrfs-grub.sh)        | btrfs, subvol, GRUB          |
| **Шифрование**        | [03-btrfs-luks-grub.sh](https://raw.githubusercontent.com/LinSwitch/install/main/03-btrfs-luks-grub.sh)    | btrfs + LUKS2 + GRUB         |
| **Современно**        | [04-btrfs-luks-sdboot.sh](https://raw.githubusercontent.com/LinSwitch/install/main/04-btrfs-luks-sdboot.sh) | btrfs + LUKS2 + systemd-boot |


📦 **Структура Btrfs (скрипты 02-04)**
  
    @          → /
    @home      → /home
    @snapshots → /.snapshots   # для Timeshift
    @log       → /var/log
    @pkg       → /var/cache/pacman/pkg
    @tmp       → /var/tmp
    @swap      → /.swap        # swapfile создаётся отдельной командой

    
---

## 🚀 Быстрый старт
>⚠️ ВНИМАНИЕ: этот скрипт удалит все данные с выбранного диска.
Перед запуском убедитесь, что выбрали правильный диск.

1. **Скачай ISO Arch** с [archlinux.org](https://archlinux.org/download/).
2. **Загрузись** с Arch ISO и **подключи интернет**.
3. **Скачай скрипт**:
   ```bash
   curl -LO https://raw.githubusercontent.com/LinSwitch/arch-install/main/название_скрипта
   chmod +x название_скрипта
   ```
4. **Запусти установку**:
   ```bash
   ./название_скрипта

    Примеры:
    01-ext4-grub.sh — самый простой.
    04-btrfs-luks-sdboot.sh — максимально «продвинутый».
5. Перезагрузись — Arch готов!

---
## 📹 Видео-инструкция

Смотреть на YouTube — пошаговая установка в реальном времени.

---
## 📜 Лицензия

MIT — используйте, меняйте, улучшайте.
