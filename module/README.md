# Nothing Phone (1) WLAN graceful failure v1.3 — TEST

**Только Spacewar 2509261631, ядро 5.4.274-qgki-g4670d6bdb795, слот A.**
Экспериментальный патч драйвера QCA6750. На телефоне v1.3 пока не проверен.
Аппаратная причина сбоев MHI/PCIe сохраняется; успешное восстановление и
отсутствие дальнейших перезагрузок не гарантируются.

## Изменения

v1.2 оставлял Android в работе, но намеренно возвращал -EIO из reinit.
В дампах 19–21 октября драйвер оставался `is_driver_recovering 1`, после чего
включение Wi-Fi завершалось таймаутом. WPSS мог сообщать `FW is ready`,
но полноценная инициализация драйвера не выполнялась.

v1.3 возвращает штатный путь `hdd_wlan_re_init`, запускающий модули и адаптеры.
Shutdown и reinit отдельно захватывают новую psoc-транзакцию; при занятой
транзакции обработчик возвращается без ожидания её захвата и без чужого stop.
Перед инициализацией сохраняется ожидание уже начавшихся операций.
Каждый обработчик освобождает только свою успешно захваченную транзакцию.
Поздний callback при уже снятом состоянии recovering пропускается.

При реальной ошибке восстановления сохраняются очистка и код ошибки.
Убраны только локальные переходы к panic после неудачного восстановления;
проверки целостности стека, ShadowCallStack и глобальные аварийные таймеры
не изменяются. При отсутствии адаптера реальный reinit возвращает ошибку
через существующую очистку вместо продолжения с NULL.

Успешное восстановление снимает recovering штатным кодом. Ошибка не
маскируется под успех и не исправляется принудительным сбросом флага.
Дополнительного цикла принудительных перезапусков, rmmod/insmod или
переключения Android Wi-Fi этот модуль не запускает. Попытка реального
восстановления выполняется при штатном callback после готовности WPSS.
Bluetooth-драйверы не меняются.

## Установка и подготовка образа

1. Установить ZIP через Magisk. До подготовки нового образа не перезагружаться.
2. В Termux выполнить:

```sh
su -c 'M=/data/adb/modules_update/wlan_graceful_fail_spacewar; [ -f "$M/boot_patch.sh" ] || M=/data/adb/modules/wlan_graceful_fail_spacewar; sh "$M/boot_patch.sh"'
```

Сборщик сохраняет полный backup текущего `boot_a` и отдельный TEST-образ в
`/sdcard/Download`, с полной датой и временем в именах. Журнал находится в
`/sdcard/log/wpss_boot_build_дата_время_PID.txt`.

Сборщик читает boot-раздел; результат в раздел не записывает. Текущий kernel
проверяется по SHA-256 и сохраняется. Существующий Magisk ramdisk сохраняется;
переустановка Magisk не выполняется. Проверка готового образа повторно
распаковывает его и сравнивает kernel и ramdisk. Это не доказывает загрузку
образа или исправность Wi-Fi на телефоне.

Изменяется ранняя копия драйвера в ramdisk, а не исходный код ядра.
ZIP без нового boot-образа не заменит уже встроенный ранний драйвер.

## Допустимые входные образы

Размер boot A: 100663296 байт. Kernel внутри backup должен иметь SHA-256:

```text
2f2656528794dde2cb54f4abb613ebffb59b5528e034863aa4aedd7bef5d0fda
```

Принимаются три ранее проверенных полных boot-хеша:

```text
6285978fe6650510da801b24067bf95ef067c01b6c2c5b5d61b0c7d5425d28c8
31f4ac5d32fd375f7729be35007ada9825af838de8351563f3e5ec13589de2e4
2d43dc21a2523e98e6895a3dfed2992af2a3072492d24ad17b5d0646f2be976b
```

Для уже изменённого boot v1.2/v1.3 полный хеш может отличаться. В этом случае
сборщик требует одновременно точное ядро, Magisk ramdisk и совпадение всех
трёх ранних файлов (драйвер, SH, RC) с одним известным комплектом v1.2/v1.3.
При несовпадении сборка останавливается, а проверенный backup остаётся.

## Первая проверка

Предпочтительно временно загрузить TEST-образ с ПК:

```text
fastboot.exe boot "путь-к-TEST-образу.img"
```

Установка через OrangeFox в `Boot` слота **A** является записью образа и
не заменяет временную проверку. Перед ней нужно сохранить доступный полный
backup. Слот B не используется. Разделы data/vendor/system не прошиваются.

После запуска v1.3 загруженный WLAN build ID должен быть:

```text
e2388611edd9fe47
```

Хеш фактически подготовленного QCA6750:

```text
291cce1505c234e8425abf3eea385fe077ae8663ba1c1337c414b6d0be6b93e9
```

В Action: Громкость + — время работы; Громкость - — дополнительные действия.
На втором экране: Громкость + — один архив диагностики; Громкость - — backup
и отдельный TEST boot. Дампы всегда в `/sdcard/log`, старые дампы сохраняются.

После сбоя нужно проверить появление `wlan0`, подключение к сети и дамп.
`FW is ready` и `re-probing driver` отдельно ещё не доказывают восстановление.

## Откат

В OrangeFox восстановить сохранённый полный backup в **Boot слота A**,
затем отключить файловую подмену модуля:

```sh
touch /data/adb/modules/wlan_graceful_fail_spacewar/disable
```

Если есть ожидающее обновление, также отключить его:

```sh
[ ! -d /data/adb/modules_update/wlan_graceful_fail_spacewar ] || touch /data/adb/modules_update/wlan_graceful_fail_spacewar/disable
```

Одно отключение модуля не удаляет встроенный ранний драйвер из boot.

## Проверки вне телефона

Патч проверен на исходном ELF и точной версии v1.2: оба входа дают один
проверяемый выходной хеш; размер, секции и ABI сохраняются. Проверены записи
ELF relocation, которые загрузчик применяет после чтения изменённых команд.

20 сценариев исполняют реальные ARM64-команды внешних обработчиков с
имитацией внутренних вызовов ядра: обычный успех/ошибка, повторный callback,
занятая транзакция, отсутствующий контекст, гонка состояния, третий отказ,
неверная шина и последовательность shutdown/reinit/duplicate/shutdown.
Они проверяют владение транзакцией, освобождение ресурсов и сохранение ошибки.
Это не моделирование всего драйвера, оборудования или Android.

`source/driver_patch.json` и `source/patch_driver.py` воспроизводят бинарный
патч из точного исходного ELF или v1.2. Полные проприетарные KO в ZIP не входят.

## English

Exact Nothing Phone (1) Spacewar build 2509261631 and kernel
5.4.274-qgki-g4670d6bdb795 only. **Experimental and not yet device-tested.**
v1.3 restores the real WLAN reinit body, acquiring a fresh psoc transaction
instead of resuming a transaction that shutdown already released. A busy or
late callback does not release another owner's transaction. Normal operation
draining, real errors, stack checks and global crash controls remain enabled.
Local recovery-failure panic paths return through cleanup instead.

Install the ZIP, run the staged builder command above BEFORE reboot, and keep
the full backup. The builder produces a separate test boot in Download and
logs in `/sdcard/log`; it never flashes a block device or reinstalls Magisk.
The real kernel bytes remain unchanged. Prefer temporary `fastboot boot` for
the first test. Restore the complete boot A backup AND disable the module to
roll back. Disabling the module alone does not undo the embedded early driver.
Hardware MHI/PCIe faults remain; recovery and freedom from reboots cannot be
guaranteed. Bluetooth drivers and Android's Wi-Fi switch are not modified.
