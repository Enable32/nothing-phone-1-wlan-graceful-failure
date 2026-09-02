# Nothing Phone (1) WLAN graceful failure

Experimental, exact-build Magisk module for Nothing Phone (1). It attempts to
keep Android alive when WPSS/WLAN firmware recovery has already failed and a
duplicate driver reinitialization would otherwise trigger the identified kernel
BUG. Installer messages and Android notifications automatically follow the
device language (Russian or English).

> [!WARNING]
> This is not a hardware repair and is not a general Wi-Fi fix. It modifies a
> kernel module in memory through Magisk. An incompatible build can cause a boot
> failure. The installer refuses every unknown firmware and driver SHA-256.

## Supported device

- Nothing Phone (1), device codename `Spacewar`
- Nothing OS build `2509261631`
- Tested kernel: `5.4.274-qgki-g4670d6bdb795`
- Stock driver SHA-256: `92542a7dccb8ead32046519fbdc03e024f258e5fe7cf13e51318c389df18f27f`
- Patched driver SHA-256: `9127891857ca5d21ceacffa8a28c881235c7138496ab7ec85317b2af24057419`

## Installation

1. Download the release ZIP. Do not extract it.
2. Open Magisk → Modules → Install from storage.
3. Select the ZIP and reboot after a successful installation.
4. Verify after reboot:

   ```sh
   su -c 'sha256sum /vendor/lib/modules/qca_cld3_wlan.ko'
   ```

The installer does not contain or redistribute the proprietary WLAN driver. It
copies the exact supported driver from the phone, applies a small binary patch,
then verifies the complete output SHA-256 before installation.

Future releases can be detected through Magisk using the repository's
`update.json` metadata.

## Behaviour

- Successful automatic Wi-Fi recovery remains enabled.
- After a final recovery failure, a dangerous duplicate callback is skipped.
- The Android Wi-Fi switch is not turned off by this module.
- Notifications report a WLAN failure or a previously captured WPSS panic.
- Size-limited logs are copied to `/sdcard/log/wlan_graceful_fail`.
- The Magisk module action button exports the current logs manually.

## Emergency disable

If Android does not boot, create this file from OrangeFox/TWRP and reboot:

```sh
touch /data/adb/modules/wlan_graceful_fail_spacewar/disable
```

The original vendor partition is never overwritten.

---

# Русский

Экспериментальный Magisk-модуль только для точной сборки Nothing Phone (1).
Он пытается оставить Android работающим, когда восстановление прошивки WPSS/WLAN
уже завершилось ошибкой, а повторная инициализация драйвера могла вызвать
выявленный kernel BUG. Язык установщика и уведомлений выбирается автоматически:
русский или английский.

> [!WARNING]
> Это не ремонт аппаратной части и не универсальное исправление Wi-Fi. Модуль
> изменяет драйвер ядра через подмену Magisk. Несовместимая версия может нарушить
> загрузку. Установщик отклоняет неизвестную прошивку или SHA-256 драйвера.

## Поддерживаемое устройство

- Nothing Phone (1), кодовое имя `Spacewar`
- Сборка Nothing OS `2509261631`
- Проверенное ядро: `5.4.274-qgki-g4670d6bdb795`
- SHA-256 штатного драйвера: `92542a7dccb8ead32046519fbdc03e024f258e5fe7cf13e51318c389df18f27f`
- SHA-256 изменённого драйвера: `9127891857ca5d21ceacffa8a28c881235c7138496ab7ec85317b2af24057419`

## Установка

1. Скачайте ZIP из раздела Releases, не распаковывая его.
2. Откройте Magisk → Модули → Установить из хранилища.
3. Выберите ZIP и после успешной установки перезагрузите телефон.
4. После запуска проверьте:

   ```sh
   su -c 'sha256sum /vendor/lib/modules/qca_cld3_wlan.ko'
   ```

В ZIP нет фирменного WLAN-драйвера. Установщик копирует с телефона точную
поддерживаемую версию, применяет небольшие байтовые изменения и перед установкой
проверяет полный SHA-256 результата.

Новые версии могут определяться самим Magisk через файл `update.json` этого
репозитория.

## Поведение

- Успешное автоматическое восстановление Wi-Fi остаётся включённым.
- После окончательной ошибки опасный повторный callback пропускается.
- Модуль не выключает системный переключатель Wi-Fi.
- Уведомления сообщают об отказе WLAN или сохранённой панике WPSS.
- Ограниченные по размеру журналы копируются в `/sdcard/log/wlan_graceful_fail`.
- Кнопка действия модуля в Magisk вручную экспортирует текущие журналы.

## Аварийное отключение

Если Android не загружается, создайте из OrangeFox/TWRP файл и перезагрузитесь:

```sh
touch /data/adb/modules/wlan_graceful_fail_spacewar/disable
```

Оригинальный раздел vendor не перезаписывается.

## License / Лицензия

The scripts and documentation in this repository are licensed under the MIT
License. No proprietary Nothing/Qualcomm driver binary is included.

Скрипты и документация распространяются по лицензии MIT. Фирменный бинарный
драйвер Nothing/Qualcomm в репозиторий не включён.
