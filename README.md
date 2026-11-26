# Nothing Phone (1) WLAN Graceful Failure

Мой экспериментальный Magisk-модуль для Nothing Phone (1): я пытаюсь сохранить
работу Android и Bluetooth при сбое Wi-Fi/WPSS и восстановить Wi-Fi штатным
путём, если радиомодуль ещё способен запуститься.

**Последняя экспериментальная сборка: v1.4 volume-menu and Wi-Fi recovery TEST.**

[Скачать v1.4 TEST](https://raw.githubusercontent.com/Enable32/nothing-phone-1-wlan-graceful-failure/main/dist/Nothing-Phone-1-WLAN-v1.4-UI-RECOVERY-TEST.zip)
· [История изменений](CHANGELOG.md)
· [Исходники установленного модуля](module)

> [!CAUTION]
> Только Nothing Phone (1), Spacewar `2509261631`, ядро
> `5.4.274-qgki-g4670d6bdb795` и поддерживаемые точные SHA-256.
> Это эксперимент для конкретной сборки и вероятной аппаратной неисправности.
> Он не ремонтирует плату и не гарантирует отсутствие дальнейших перезагрузок.

## v1.4: меню по номерам и ручное восстановление Wi-Fi

Иногда у меня Wi-Fi включён, но список сетей пуст. Кнопка Android «Исправить
подключение» иногда помогала. Я добавил в модуль отдельное действие для Wi-Fi:
сначала проверить новое сканирование, затем при необходимости попросить Android
восстановить Wi-Fi и остановиться, когда появятся свежие сети или подключение.

Громкость **+** переключает номер по кругу, громкость **−** выполняет выбор:

| Номер | Действие |
| --- | --- |
| 1 | Время работы |
| 2 | Один архив диагностики |
| 3 | Восстановление Wi-Fi |
| 4 | Полный backup и отдельный TEST boot |
| 5 | Выход |

Во время пункта 3 громкость **−** отменяет дальнейшие попытки. Лимит —
**три запроса восстановления и 180 секунд**. Меню само закроется через
120 секунд без нажатий; оно не запускает выбранный пункт по таймауту.

Используется штатная `cmd wifi trigger-recovery`. Сканирование проверяется
по возрасту результатов: включённый переключатель и старый список сетей не
считаются успехом. Ошибки Binder, неизвестный формат ответа, смена WPSS RELATED
или потеря кнопок останавливают попытки. Если Wi-Fi выключен, пункт 3 сначала
запрашивает его включение. Wi-Fi и точка доступа временно прерываются.

Пункт 3 требует точный загруженный ранний драйвер v1.3
`e2388611edd9fe47` и политику WPSS RELATED. Новые попытки не отправляются
после отмены, но уже принятый Android запрос может завершиться позднее.
Команды не перезагружают Android и не перезапускают мобильную связь или
Bluetooth. Аппаратный сбой всё ещё может привести к CrashDump.

**Драйвер и ранние boot-файлы v1.3 сохранены побайтно.** Для работающего,
проверенного boot v1.3 не нужна новая прошивка boot или переустановка Magisk.
Этот пункт ещё не проверен на моём телефоне; host-тесты не заменяют такую проверку.

## Как всё началось

Мой телефон начал зависать и сам перезагружаться. Иногда он часами показывал
CrashDump и не мог загрузить Android. Бывали случаи, когда после удара о твёрдую
поверхность он всё-таки начинал запускаться. Это стало причиной подозревать
неисправность контакта, пайки, питания или радиомодуля. Какой именно компонент
повреждён, одними логами установить не удалось. Удары могут дополнительно
повредить плату и аккумулятор; повторять это не следует.

Сначала у меня не было компьютера. Я собирал в Termux с root журналы `logcat`,
`dmesg`, `pstore/ramoops`, причины загрузки и vendor ramdump. В них встречались:

```text
kernel_panic,bug
MHI_DEV_SYS_ERR
Driver reinit failed
reset_reason: subsys-restart: Resetting the Soc - wpss crashed
```

В исследованных падениях сбой Wi-Fi/WPSS сопровождался проблемой восстановления:
ошибка одной подсистемы приводила к остановке всего Android. Я начал менять
конкретные аварийные ветки драйвера и порядок его ранней загрузки.

## Первый драйвер, вторая копия и фактически загруженный QCA6750

Сначала я нашёл `/vendor/lib/modules/qca_cld3_wlan.ko`. В ранних версиях модуля
попытался обработать неудачный reinit без повторного опасного callback.
Телефон стал чаще загружаться с первого раза, но продолжал перезагружаться.

Дальнейшие дампы вывели на `osif_psoc_sync_trans_resume()`: повторный обработчик
восстановления мог обращаться к уже завершённой транзакции и попадать в BUG.
Правильный хеш изменённого файла на диске не объяснял все последующие стеки.

Затем я нашёл вторую копию —
`/vendor/lib/modules/5.4-gki/qca_cld3_wlan.ko` — и команды загрузчика для обоих
каталогов в `init.target.rc`. Поэтому v0.4 начала обрабатывать обе копии,
учитывая разные смещения и ELF-релокации. Однако наличие двух файлов и их
хешей ещё не доказывало, какая реализация действительно работает в памяти.

Позже проверка идентичности загруженного модуля указала на вариант
`/vendor/lib/modules/qca_cld3_qca6750.ko`. Для него потребовался отдельный патч.
В v1.3 я проверяю не только файл на диске, но и build ID загруженного драйвера.
Два ранее обработанных варианта `qca_cld3_wlan.ko` сохранены для этой сборки.

## Что именно я отключил и почему появился ранний boot-патч

Я обошёл конкретные локальные ветки panic/BUG при неудачном восстановлении,
направив выполнение в существующую очистку с возвратом ошибки. Ранние
аварийные версии также блокировали автоматический WLAN reinit.

Отдельно у WPSS обнаружилась политика `SYSTEM`: сбой подсистемы мог требовать
сброса всего SoC. Ранний guard выставляет `restart_level=RELATED`.
Обычный Magisk `service.sh` для части загрузочных сбоев запускался слишком
поздно, поэтому потребовались ранние файлы `overlay.d` в boot ramdisk.

Подмена драйвера также должна происходить до `vendor_modprobe`. Простая
установка ZIP меняет файлы Magisk, но не заменяет уже встроенный в boot ранний
драйвер. Сборщик создаёт отдельный образ с ранним QCA6750 и WPSS guard.

**Исходный код ядра здесь не пересобирается.** Меняется копия boot-образа:
в ramdisk добавляются ранние файлы, а kernel внутри сохраняется и проверяется
по SHA-256. Глобальные watchdog, проверки стека и ShadowCallStack сохраняются.

## От v1.2 к v1.3: возвращение Wi-Fi

v1.2 намеренно возвращала ошибку `-EIO` из reinit. Android мог продолжать
работать, но Wi-Fi оставался в `is_driver_recovering 1`: сообщение
`FW is ready` ещё не означало, что адаптеры заново инициализированы.

В v1.3 я вернул настоящий `hdd_wlan_re_init`. Shutdown и reinit отдельно
захватывают новую psoc-транзакцию; каждый обработчик освобождает только ту,
которую успешно захватил сам. При занятой транзакции обработчик не ждёт её
захвата и не освобождает чужую. Поздний повторный callback пропускается,
если состояние восстановления уже снято.

При реальной ошибке остаются очистка и её код возврата. При отсутствии
адаптера используется ветка ошибки вместо продолжения с NULL. Модуль не
запускает собственный бесконечный цикл перезапусков, `rmmod/insmod` или
принудительное переключение Wi-Fi. Драйверы Bluetooth не подменяются.

## Что удалось подтвердить на моём телефоне

В дампе от 15 ноября 2026 я увидел завершённое восстановление: после
`MHI_DEV_SYS_ERR` WPSS прошёл RELATED restart, прошивка сообщила о готовности,
драйвер завершил reinit, а `wlan0` снова подключился к сети в той же загрузке
Android. Это подтверждает конкретный успешный случай автоматического
восстановления, а не исправность оборудования или всех аварийных сценариев.

В тот же день был и полный перезапуск телефона. Перед ним отдельный native
crash `system_server` содержал:

```text
FORTIFY: memcpy: prevented 116-byte write into 92-byte buffer
SystemProperties::ReadCallback
PropertyInvalidatedCache.getCurrentNonce
```

Дальше Android циклически перезапускал zygote. Причина неверного состояния
системного свойства и точный механизм полной перезагрузки ещё исследуются.
Модуль подмены устройства под Pixel — одна из проверяемых гипотез; его вина
не доказана. Все перезагрузки нельзя автоматически приписывать Wi-Fi.

Полные пользовательские логи и дампы памяти в этот репозиторий не включены.

## Совместимость и проверяемая идентичность

| Параметр | Значение |
| --- | --- |
| Телефон | Nothing Phone (1), `Spacewar` |
| Сборка | `2509261631` |
| Ядро | `5.4.274-qgki-g4670d6bdb795` |
| Boot-builder | Только слот `_a`, размер boot A `100663296` байт |
| Root | Уже установленный Magisk ramdisk; на моём телефоне проверялся Magisk 31.0 |
| Build ID QCA6750 v1.3 | `e2388611edd9fe47` |
| Свободное место | Для boot-builder не менее 1 ГиБ |

SHA-256 подготовленного QCA6750:

```text
291cce1505c234e8425abf3eea385fe077ae8663ba1c1337c414b6d0be6b93e9
```

SHA-256 kernel внутри поддерживаемого boot:

```text
2f2656528794dde2cb54f4abb613ebffb59b5528e034863aa4aedd7bef5d0fda
```

Установщик принимает только известные входные хеши. Boot-builder также
проверяет точное ядро, Magisk ramdisk и поддерживаемую идентичность исходного
образа. Обновление Nothing OS или неизвестный boot требуют отдельного анализа.

## Установка v1.4 поверх проверенной v1.3

1. Скачать ZIP по ссылке в начале README.
2. В Magisk выбрать **Модули → Установить из хранилища** и установить ZIP.
3. Проверенный ранний boot v1.3 оставить. Чтобы открыть новое меню сразу,
   без перезагрузки, выполнить в Termux:

```sh
su -c 'M=/data/adb/modules_update/wlan_graceful_fail_spacewar; [ -f "$M/action.sh" ] || M=/data/adb/modules/wlan_graceful_fail_spacewar; sh "$M/action.sh"'
```

При следующей обычной загрузке Magisk активирует обновление. Для пункта 3
на начальном экране меню нажать **+ два раза**, затем **−**.

## Первая установка с неподготовленным boot

v1.4 наследует ранний драйвер и сборщик v1.3. Если этот boot ещё не подготовлен,
пункт 3 откажется делать попытки. Пункт 4 снимает полный датированный backup
`boot_a`, создаёт отдельный TEST-образ и повторно проверяет его. Оба файла
сохраняются в `/sdcard/Download`, в раздел сборщик ничего не записывает.

Существующий Magisk ramdisk и kernel сохраняются. Переустановка Magisk именно
для этого патча не требуется. Нужен не менее 1 ГиБ свободного места.

Для первого запуска предпочтительна временная загрузка с компьютера:

```bat
fastboot.exe boot "Nothing-Phone-1_boot-a_QCA6750-EARLY-v1.3-TEST_ДАТА_ВРЕМЯ.img"
```

Постоянная прошивка Boot слота A — отдельная операция. До неё должны быть
доступны полный backup и способ его восстановить. Слот B не используется.

## Логи

Все публичные диагностические файлы находятся в **`/sdcard/log`**.
Пункт 2 создаёт один архив. Пункт 3 создаёт один отчёт вида
`wifi_recovery_ГГГГ-ММ-ДД_ЧЧ-ММ-СС_PID.txt`; его ограниченная копия включается
в следующий диагностический архив. Старые архивы сохраняются.

При ошибке пункта 3 нужен этот отчёт; повторять попытки бесконечно не следует.
В отчётах могут быть локальные названия и адреса сетей, поэтому сами отчёты
не публикуются в репозитории. Установщик и меню поддерживают русский и английский.

## Откат

В OrangeFox восстановить сохранённый полный backup в **Boot слота A**.
Затем отключить файловую подмену модуля:

```sh
touch /data/adb/modules/wlan_graceful_fail_spacewar/disable
[ ! -d /data/adb/modules_update/wlan_graceful_fail_spacewar ] || touch /data/adb/modules_update/wlan_graceful_fail_spacewar/disable
```

## Архив, исходники и проверки

В `dist` доступны новая v1.4 TEST и неизменённый исходный ZIP v1.3.
Контрольные суммы обоих архивов находятся в [dist/SHA256SUMS](dist/SHA256SUMS).
`module/` соответствует содержимому нового ZIP v1.4.

При разработке v1.4 выполнены **18 host-тестов** с подменой Android и аппаратных
операций: навигация меню, очистка обработчика кнопок, возраст сканирования,
остановка по успеху/отмене/лимиту, несовместимый драйвер/политика, ошибки Binder
и запрет параллельного запуска. Они исполняют реальный shell-код и парсеры.
На телефоне новая команда восстановления ещё требует проверки.

Исторические отчёты v1.3 о 20 сценариях обработчиков и 17 проверках упаковки
сохранены в `module/source/`. Бинарный патч не менялся, эти сценарии при
публикации v1.4 заново не запускались. Подтверждено побайтное совпадение
драйверного манифеста, функций бинарного патча, сборщика и ранних boot-файлов.

Проверить архив: `sh tools/verify.sh`.
Проверить новое поведение на host: `python3 tests/test_recovery.py`.
Пересобрать ZIP: `sh tools/build.sh`; пересобранный файл имеет суффикс
`-repacked.zip` и может отличаться хешем упаковки.

Основной `update.json` сохраняет прежний канал v0.9; TEST-метаданные v1.4
находятся в `update-test.json`. Новая v1.4 также использует этот TEST-канал.
Полные фирменные `.ko`, boot-образы и пользовательские дампы не публикуются.

- [AOSP WifiShellCommand: trigger-recovery](https://android.googlesource.com/platform/packages/modules/Wifi/+/10cc79ed05/service/java/com/android/server/wifi/WifiShellCommand.java)
- [AOSP ScanResultUtil: возраст результатов](https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/util/ScanResultUtil.java)

## English summary

v1.4 TEST adds a numbered volume-key menu and manual Wi-Fi userspace recovery.
Volume Up cycles 1–5; Volume Down runs the selection and cancels further
recovery requests while running. A fresh scan is tried first, followed by at
most three Android recovery requests within a 180-second budget. Fresh scan
results or a reported connection plus active wlan0 stop further requests.
Cached scans and the enabled switch alone do not count. Binder errors, lost
keys and guard changes stop the run. Wi-Fi/hotspot may disconnect temporarily.

The v1.3 binary patch and early boot files are unchanged. Existing verified
v1.3 boot and Magisk need no reflashing for this update. The new userspace
feature has host behavioural tests and is not yet device-verified. Hardware
crashes remain possible. One dated report is saved under /sdcard/log.


This is my exact-build experiment for a Nothing Phone (1) with recurring
WPSS/WLAN failures and a suspected hardware fault. After investigating both
`qca_cld3_wlan.ko` locations, I identified the loaded QCA6750 variant and the
need to mount its patch before `vendor_modprobe`.

v1.3 TEST restores real WLAN reinitialization with fresh psoc transaction
ownership, retains real error/cleanup paths, and bypasses specific local
recovery-failure panic branches. An early boot-ramdisk guard sets WPSS to
RELATED. Stack checks, global watchdogs and Bluetooth drivers remain intact.

A November 15 dump confirmed one completed WPSS restart, WLAN reinit and
network reconnection in the same Android boot. A separate system_server
FORTIFY crash is under investigation; this is not a claim that all reboot
causes have been fixed.

The builder preserves the existing Magisk ramdisk and kernel, creates a dated
full boot A backup plus a separate test image, and never flashes automatically.
Reinstalling Magisk is not required by this builder. Test with `fastboot boot`
first; rolling back the embedded early driver requires restoring the full boot
backup as well as disabling the module. Diagnostics go to `/sdcard/log`.

Only Spacewar build `2509261631`, the exact documented kernel and known input
hashes are accepted. The original v1.3 ZIP remains archived unchanged; the current module sources
include the v1.4 userspace additions. Hardware repair and universal reboot prevention are outside the
scope of this module.
