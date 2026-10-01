# WLAN graceful failure v0.9 — кратко / quick guide

Только для Nothing Phone (1) `Spacewar`, сборки `2509261631` и Magisk 28.1.
Это экспериментальный аварийный обход аппаратного сбоя WPSS/WLAN, не ремонт.

Only for Nothing Phone (1) `Spacewar`, build `2509261631`, and Magisk 28.1.
This is an experimental containment workaround for WPSS/WLAN hardware failure,
not a repair.

## Action / Действие

1. Первый экран / First page:
   - Volume Up: uptime / время работы;
   - Volume Down: more / дополнительные действия.
2. Второй экран / Second page:
   - Volume Up: one diagnostic `.tar.gz` / один архив диагностики;
   - Volume Down: timestamped `boot_a` backup plus a separate WPSS-RELATED
     patched copy in `/sdcard/Download`.

Action never flashes a partition. / Action никогда не прошивает раздел.

The boot builder accepts only slot `_a`, build `2509261631`, boot size
`100663296`, and SHA-256:

```text
6285978fe6650510da801b24067bf95ef067c01b6c2c5b5d61b0c7d5425d28c8
```

Сначала тестируйте патченый образ через `fastboot boot`, не `fastboot flash`.
Test the patched image with `fastboot boot` first, not `fastboot flash`.

Аварийное отключение / Emergency disable from OrangeFox:

```sh
touch /data/adb/modules/wlan_graceful_fail_spacewar/disable
```
