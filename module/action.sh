#!/system/bin/sh

LOGROOT="/data/adb/wlan_graceful_fail_logs"
PUBLIC_LOGROOT="/sdcard/log/wlan_graceful_fail"
DEVICE_LOCALE="$(getprop persist.sys.locale)"
[ -n "$DEVICE_LOCALE" ] || DEVICE_LOCALE="$(getprop ro.product.locale)"

mkdir -p "$PUBLIC_LOGROOT" 2>/dev/null
cp -f "$LOGROOT"/console-ramoops-*.txt "$PUBLIC_LOGROOT"/ 2>/dev/null
cp -f "$LOGROOT"/events.log* "$PUBLIC_LOGROOT"/ 2>/dev/null
cp -f "$LOGROOT"/kernel.log* "$PUBLIC_LOGROOT"/ 2>/dev/null
chmod 0755 "$PUBLIC_LOGROOT" 2>/dev/null
chmod 0644 "$PUBLIC_LOGROOT"/* 2>/dev/null

case "$DEVICE_LOCALE" in
    ru*|RU*|*_RU*|*-RU*)
        echo "Журналы скопированы: Внутренняя память/log/wlan_graceful_fail"
        cmd notification post -t "Журналы Wi-Fi сохранены" wlan_logs_exported \
            "Папка: Внутренняя память/log/wlan_graceful_fail" >/dev/null 2>&1
        ;;
    *)
        echo "Logs copied to: Internal storage/log/wlan_graceful_fail"
        cmd notification post -t "Wi-Fi logs saved" wlan_logs_exported \
            "Folder: Internal storage/log/wlan_graceful_fail" >/dev/null 2>&1
        ;;
esac

