# Changelog / История изменений

## 1.4 TEST — 2026-11-26

- Меню Action по номерам 1–5: громкость + переключает выбор, громкость −
  выполняет пункт. Отпускания/удержание не считаются новыми нажатиями.
  За 120 секунд без выбора меню закрывается без запуска действия.
- Новый пункт 3: ручное восстановление Wi-Fi через Android trigger-recovery.
  Сначала пробует сканирование, затем максимум три запроса за 180 секунд.
- Остановка при свежих результатах сканирования или подключении с активным
  wlan0. Возраст записей проверяется относительно запроса; старый кеш,
  включённый переключатель и один интерфейс сами по себе не означают успех.
- Громкость − во время выполнения отменяет дальнейшие запросы. При ошибках
  Binder, изменении RELATED или потере кнопок работа прекращается.
- Проверяются точный загруженный v1.3 драйвер, WPSS RELATED, сборка и команды
  Android. Для отдельных команд есть таймаут; параллельный запуск блокируется.
- Один текстовый отчёт в /sdcard/log; его ограниченная копия входит в общий дамп.
- Драйверный патч, boot-builder и ранний payload v1.3 побайтно сохранены.
  Для работающего boot v1.3 новая прошивка boot и установка Magisk не требуются.
- TEST-канал обновлён отдельно; основной update.json остаётся на v0.9.
- Выполнены 18 host-тестов реального shell-кода/парсеров с имитацией Android.
  Новая userspace-функция ещё требует проверки на телефоне.

English: numbered Action menu, bounded manual Wi-Fi recovery, freshness-aware
scan checks, cancellation, per-command timeouts and local reports. Exact loaded
v1.3 driver and RELATED are required. The v1.3 binary patch and boot payload are
unchanged. Host-tested, not yet device-verified; hardware crashes remain possible.

## 1.3 TEST — опубликовано 2026-11-25, исходный архив 2026-10-21

- Опубликованы исходный ZIP v1.3 и совпадающие с ним исходники без изменения
  скриптов установленной сборки.
- Для QCA6750 возвращён настоящий WLAN reinit с отдельным захватом
  psoc-транзакции в shutdown/reinit. Обработчик освобождает только свою
  транзакцию; повторный callback и занятая транзакция обрабатываются отдельно.
- Реальные ошибки возвращаются через очистку. Локальные recovery-failure
  panic/BUG обходятся; глобальные watchdog, защита стека и Bluetooth-драйверы
  сохраняются.
- Ранний boot-builder монтирует QCA6750 до vendor_modprobe и сохраняет WPSS
  RELATED. Kernel и существующий Magisk ramdisk проверяются и сохраняются.
  Повторная установка Magisk сборщику не нужна; автоматической прошивки нет.
- На устройстве подтверждён один успешный цикл WPSS restart → WLAN reinit →
  подключение к сети в той же загрузке Android (дамп от 2026-11-15).
- Отдельный native FORTIFY crash system_server перед полным перезапуском
  исследуется отдельно. Причастность Pixel-spoofing модуля не подтверждена.
- Все публичные диагностические файлы сохраняются в /sdcard/log.
- Основной update.json оставлен на v0.9; TEST доступен по отдельной ссылке
  и описан в update-test.json.
- Исходные отчёты о 20 проверках обработчиков и 17 проверках упаковки включены
  как исторические отчёты, а не как новый аппаратный тест.
- Повторная проверка публикации: ZIP/CRC, точное совпадение файлов с архивом,
  синтаксис shell/Python, JSON, границы патчей и идентичность QCA6750.
- ZIP SHA-256:
  `7906ff6c098e2edb50ac29b1e83c82aeacf09088cabf36305fa616a125efcabc`.

English: publish the unchanged v1.3 owned-recovery TEST archive and its sources,
document one confirmed on-device WLAN recovery, preserve existing Magisk and
kernel in the boot builder, and separate the unresolved system_server property
read crash from the WLAN recovery evidence. This remains experimental; hardware
faults and other reboot causes are not fixed by this release.

## 1.2 TEST — история исследования

- Добавлен отдельный ранний QCA6750 и RELATED guard.
- Reinit намеренно возвращал -EIO; WPSS мог восстановиться, но WLAN оставался
  в состоянии recovering без полноценного запуска адаптеров.
- Added early QCA6750 mounting; intentionally blocked real reinit. Superseded
  by the v1.3 recovery experiment.

## 1.0–1.1 TEST — история исследования

- Исследована ранняя загрузка до vendor_modprobe и фактическая идентичность
  QCA6750; расширена проверка уже рутованных boot-образов.
- Investigated early driver loading and the active QCA6750 variant.

## 0.9

- Added a two-page bilingual volume-key Action menu.
- Added a third Action choice that creates a full timestamped `boot_a` backup,
  injects the early WPSS `RELATED` guard into a copy, verifies the injected
  files, and saves the patched copy to `/sdcard/Download`.
- The boot builder never writes to a block device and accepts only the exact
  Spacewar build, slot, partition size, and confirmed boot SHA-256.
- Added an early-policy `post-fs-data` fallback and guard logging.
- Integrated the v0.7 no-auto-reinit path and v0.8 three-probe BUG bypass for
  both competing WLAN driver paths.
- Reworked the installer to patch supported driver states on-device; no full
  proprietary WLAN binaries are stored in the repository or ZIP.
- Updated the detailed first-person investigation story and recovery guide.

- Добавлено двухуровневое меню Action на кнопках громкости.
- Добавлен третий пункт: полный backup `boot_a` с датой и временем, внедрение
  раннего WPSS `RELATED` guard только в копию, проверка файлов и сохранение
  патченого образа в `/sdcard/Download`.
- Boot-builder никогда не пишет в раздел и принимает только точные модель,
  сборку, слот, размер и подтверждённый SHA‑256 `boot_a`.
- Добавлена поздняя страховка `post-fs-data` и журнал ранней политики.
- Объединены защита v0.7 от WLAN auto-reinit и обход v0.8 для BUG после трёх
  неудачных probe в обеих конкурирующих копиях драйвера.
- Установщик меняет только поддерживаемые драйверы на устройстве; полных
  фирменных WLAN-бинарников в репозитории и ZIP нет.

## 0.8

- Routed the third consecutive WLAN probe failure around `__qdf_bug()` into
  the driver's existing cleanup path.
- Направлена третья неудачная попытка WLAN probe мимо `__qdf_bug()` в штатную
  ветку очистки драйвера.

## 0.7

- Blocked automatic WLAN reinit callbacks after a WPSS crash when the first
  reinit could already panic in `osif_psoc_sync_trans_resume()`.
- Заблокированы автоматические callback реинициализации WLAN после сбоя WPSS.

## 0.4

- Patched both competing WLAN driver paths and added bilingual Magisk support.
- Начали изменяться обе конкурирующие копии WLAN-драйвера; добавлен двуязычный
  установщик Magisk.
