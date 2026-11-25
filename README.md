# Nothing Phone (1) WLAN Graceful Failure

Мой экспериментальный Magisk-модуль для Nothing Phone (1): я пытаюсь сохранить
работу Android и Bluetooth при сбое Wi-Fi/WPSS и восстановить Wi-Fi штатным
путём, если радиомодуль ещё способен запуститься.

**Последняя экспериментальная сборка: v1.3 QCA6750 owned-recovery TEST.**

[Скачать v1.3 TEST](https://raw.githubusercontent.com/Enable32/nothing-phone-1-wlan-graceful-failure/main/dist/Nothing-Phone-1-WLAN-v1.3-RECOVERY-TEST.zip)
· [История изменений](CHANGELOG.md)
· [Исходники установленного модуля](module)

> [!CAUTION]
> Только Nothing Phone (1), Spacewar `2509261631`, ядро
> `5.4.274-qgki-g4670d6bdb795` и поддерживаемые точные SHA-256.
> Это эксперимент для конкретной сборки и вероятной аппаратной неисправности.
> Он не ремонтирует плату и не гарантирует отсутствие дальнейших перезагрузок.

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

## Установка v1.3 TEST

1. Скачать ZIP по ссылке в начале README.
2. В Magisk открыть **Модули → Установить из хранилища** и выбрать ZIP.
3. До перезагрузки подготовить новый TEST boot. Можно использовать Action
   либо выполнить в Termux:

```sh
su -c 'M=/data/adb/modules_update/wlan_graceful_fail_spacewar; [ -f "$M/boot_patch.sh" ] || M=/data/adb/modules/wlan_graceful_fail_spacewar; sh "$M/boot_patch.sh"'
```

Сборщик читает текущий `boot_a`, сохраняет его полный backup с датой и временем,
готовит отдельный TEST-образ и повторно проверяет результат. Оба файла лежат
в `/sdcard/Download`. Сам сборщик в раздел ничего не записывает.

**Повторно устанавливать Magisk для этого патча не требуется:** сборщик работает
с копией уже рутованного boot и проверяет, что в результате сохранён Magisk
ramdisk. Существующие байты kernel также проверяются до и после упаковки.

Для первого запуска предпочтительна временная загрузка с компьютера:

```bat
fastboot.exe boot "Nothing-Phone-1_boot-a_QCA6750-EARLY-v1.3-TEST_ДАТА_ВРЕМЯ.img"
```

Постоянная прошивка Boot слота A — отдельная операция. Перед ней должны быть
доступны полный backup и способ его восстановить. Слот B сборщик не использует.
Отключение Magisk-модуля само по себе не убирает ранний драйвер из boot.

## Action и логи

| Экран | Громкость + | Громкость − |
| --- | --- | --- |
| Первый | Время работы | Дополнительные действия |
| Второй | Один архив диагностики | Полный backup и отдельный TEST boot |

Надписи установщика и меню выбираются на русском или английском по языку Android.
Диагностика сохраняется в **`/sdcard/log`**. Сборщик записывает туда же
`wpss_boot_build_ДАТА_ВРЕМЯ_PID.txt`. Старые диагностические архивы сохраняются.

После сбоя проверяются build ID загруженного драйвера, RELATED, успешный
reinit, наличие `wlan0` и подключение к сети. Один хеш файла или `FW is ready`
не заменяет эти проверки.

## Откат

В OrangeFox восстановить сохранённый полный backup в **Boot слота A**.
Затем отключить файловую подмену модуля:

```sh
touch /data/adb/modules/wlan_graceful_fail_spacewar/disable
[ ! -d /data/adb/modules_update/wlan_graceful_fail_spacewar ] || touch /data/adb/modules_update/wlan_graceful_fail_spacewar/disable
```

## Архив, исходники и проверки

В `dist` опубликован исходный ZIP от 21 октября 2026, без перепаковки и без
изменения его скриптов. Его SHA-256:

```text
7906ff6c098e2edb50ac29b1e83c82aeacf09088cabf36305fa616a125efcabc
```

`module/` побайтно соответствует содержимому этого ZIP. Поэтому его внутренний
README сохраняет статус на момент создания — «ещё не проверен на телефоне».
Актуальный результат проверки на устройстве приведён выше в этом README.

В `module/source/` находятся описание бинарных изменений, инструменты
воспроизведения и первоначальные отчёты: 20 сценариев обработки транзакций и
17 проверок упаковки/защитных условий. Это ограниченные проверки с имитацией
внутренних вызовов, а не моделирование всего драйвера и оборудования.

При публикации повторно проверены ZIP/CRC, совпадение исходников с архивом,
синтаксис shell и Python, JSON, границы патчей и ожидаемая идентичность драйвера.
Повторного аппаратного теста при публикации не выполнялось. Полные фирменные
`.ko`, boot-образы и дампы памяти в ZIP и репозитории отсутствуют.

Проверить опубликованный архив: `sh tools/verify.sh`.
Пересобрать архив из исходников: `sh tools/build.sh`; результат имеет суффикс
`-repacked.zip` и может иметь другой SHA-256 при том же содержимом файлов.

v1.3 остаётся **TEST** и распространяется отдельной ссылкой. Основной
`update.json` сохраняет прежний канал v0.9; метаданные v1.3 лежат в
`update-test.json`.

## English summary

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
hashes are accepted. The original v1.3 ZIP and its source files are published
unchanged. Hardware repair and universal reboot prevention are outside the
scope of this module.
