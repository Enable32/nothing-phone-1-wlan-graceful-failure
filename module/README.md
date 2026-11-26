# Nothing Phone (1) WLAN Graceful Failure v1.4 — TEST

Только Spacewar `2509261631`, ядро `5.4.274-qgki-g4670d6bdb795`.
v1.4 добавляет меню и ручное восстановление Wi-Fi. Драйвер, его бинарный патч
и ранние boot-файлы сохранены от v1.3 без изменений.

## Меню Action

Громкость **+** переключает номер по кругу, громкость **−** выполняет выбранный
пункт. Меню начинает с пункта 1; без нажатий оно закроется через 120 секунд.
Отпускания и удержание кнопки не считаются новыми нажатиями.

| Номер | Действие |
| --- | --- |
| 1 | Время работы телефона |
| 2 | Один архив диагностики в `/sdcard/log` |
| 3 | Восстановление Wi-Fi, максимум три попытки |
| 4 | Полный backup boot A и отдельный TEST boot |
| 5 | Выход |

При потере доступа к кнопкам меню может создать диагностический архив, но
не запускает восстановление или сборщик boot самостоятельно.

## Как работает пункт 3

1. Проверяется точная сборка, уже загруженный драйвер v1.3 с build ID
   `e2388611edd9fe47`, WPSS `RELATED`, готовность Android и наличие нужных
   команд `cmd wifi`. Одновременно допускается один запуск.
2. Если Android сообщает о подключении и `wlan0` активен, новых перезапусков
   не будет. Если Wi-Fi выключен, запрашивается его включение.
3. Сначала выполняется сканирование без перезапуска.
4. Если результата нет, используется штатный механизм Android
   `cmd wifi trigger-recovery`, после чего запрашивается новое сканирование.
5. При появлении свежих сетей либо состояния подключения попытки прекращаются.
   Включённый переключатель, наличие интерфейса и старый список сетей сами
   по себе не считаются успехом. Для свежих результатов проверяется возраст
   записей относительно запроса сканирования, с пределом пять секунд.

Ограничение — **три запроса восстановления и 180 секунд общего времени**.
Отдельный вызов Android ограничен восемью секундами и оставшимся бюджетом
времени; зависший клиент получает завершающий сигнал. При смене политики WPSS,
ошибке Binder, неподдерживаемом формате ответа или потере кнопок скрипт
останавливается и не отправляет следующий запрос восстановления.

Во время выполнения **громкость − отменяет дальнейшие попытки**. Уже принятый
Android запрос может закончиться после отмены. При зависшей команде реакция
может занять до её таймаута. Если рядом нет доступных точек, лимит также
завершит работу; это не доказывает поломку радио.

Wi-Fi и точка доступа временно прерываются. Команды не перезапускают мобильную
связь, Bluetooth, Android или system_server, не выгружают `.ko` и не меняют
boot-разделы. Аппаратный сбой всё ещё может вызвать CrashDump: этот скрипт
не может гарантировать восстановление или удержать аварийно падающее ядро.

## Установка поверх работающей v1.3

Установить ZIP через Magisk. Если ранний boot v1.3 уже проверен и загружен,
пересобирать или прошивать boot и переустанавливать Magisk не требуется.

Чтобы запустить новое меню сразу, пока файлы модуля ожидают перезагрузки:

```sh
su -c 'M=/data/adb/modules_update/wlan_graceful_fail_spacewar; [ -f "$M/action.sh" ] || M=/data/adb/modules/wlan_graceful_fail_spacewar; sh "$M/action.sh"'
```

При следующей обычной загрузке Magisk активирует установленное обновление.
Принудительная перезагрузка ради проверки меню не нужна.

Ручной запуск только восстановления из уже активного модуля:

```sh
su -c 'sh /data/adb/modules/wlan_graceful_fail_spacewar/wifi_recover.sh'
```

## Первая установка и boot

ZIP сохраняет точные проверки входных драйверов v1.3. Если ранний образ ещё
не подготовлен, пункт 3 откажется выполнять попытки. Пункт 4 использует
сборщик v1.3: он создаёт полный датированный backup boot A и отдельный образ
в `/sdcard/Download`, сохраняет существующий Magisk ramdisk и kernel и ничего
не прошивает автоматически. Предпочтительна временная проверка `fastboot boot`
перед постоянной установкой. Понадобится не менее 1 ГиБ свободного места.

Ожидаемый QCA6750 SHA-256:

```text
291cce1505c234e8425abf3eea385fe077ae8663ba1c1337c414b6d0be6b93e9
```

Это обновление интерфейса и userspace-инструментов; новый вариант бинарного
патча ядра или драйвера в v1.4 не добавлялся.

## Логи и откат

Одна попытка ручного восстановления создаёт один текстовый отчёт:

```text
/sdcard/log/wifi_recovery_ГГГГ-ММ-ДД_ЧЧ-ММ-СС_PID.txt
```

В нём есть результаты команд, причина остановки и число запросов. Ограниченная
копия последнего отчёта включается в общий архив диагностики пункта 2.
Сети и их адреса остаются в локальном отчёте; публиковать его в репозитории
вместе с исходниками не нужно.

Если процесс был аварийно убит, может остаться lock. Скрипт не захватывает
чужой lock; при обычной загрузке служба удаляет lock уже завершившегося процесса.

Откат только меню: установить предыдущий ZIP v1.3. Если требуется убрать ранний
драйвер, восстановить полный сохранённый boot A через OrangeFox и отключить
модуль. Отключение модуля само по себе не удаляет файлы из ramdisk boot.

## Проверки и источники

Host-проверки в `tests/test_recovery.py` репозитория выполняют реальный shell
код с подменой Android/аппаратных операций: переходы меню, очистка обработчика
кнопок, возраст результатов, остановка после успеха, отмена, лимиты, ошибочный
драйвер/политика, ошибки Binder с нулевым кодом возврата и параллельный запуск.
Это не проверка реального восстановления на Nothing Phone (1).

Исторические отчёты v1.3 в `source/` относятся к неизменённому бинарному патчу.

- [AOSP WifiShellCommand: trigger-recovery](https://android.googlesource.com/platform/packages/modules/Wifi/+/10cc79ed05/service/java/com/android/server/wifi/WifiShellCommand.java)
- [AOSP ScanResultUtil: возраст результатов](https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/util/ScanResultUtil.java)

## English

v1.4 TEST adds a numbered volume-key Action menu and bounded manual userspace
Wi-Fi recovery. Volume Up cycles 1–5, Volume Down runs the selection. During
recovery Volume Down cancels further requests. Options: uptime, one dump,
Wi-Fi recovery, backup/test boot, exit.

Recovery requires the exact loaded v1.3 driver and WPSS RELATED. It tries a
scan first, then at most three Android `cmd wifi trigger-recovery` requests
within 180 seconds. It stops for fresh scan results or Android-reported
connection plus an active wlan0; cached results and an enabled switch alone
are insufficient. Binder failures, unknown responses and lost key input stop
further requests. Individual client commands have timeouts.

An already accepted Android recovery may finish after cancellation. Hardware
failure may still cause CrashDump. There is no kernel module unloading, global
reboot, mobile/Bluetooth reset or boot flashing. The v1.3 driver and early boot
payload are unchanged. Existing verified v1.3 boot and Magisk need no reflashing
for this UI update. Logs are written to `/sdcard/log`.

This release has host behavioural tests and still needs device verification.
