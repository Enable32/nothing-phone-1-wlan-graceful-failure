# Changelog / История изменений

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
