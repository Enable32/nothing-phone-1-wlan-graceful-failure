#!/system/bin/sh

MODDIR=${0%/*}
STATE_FILE="$MODDIR/.notified_this_boot"
LOGROOT="/data/adb/wlan_graceful_fail_logs"
EVENT_LOG="$LOGROOT/events.log"
PUBLIC_LOGROOT="/sdcard/log/wlan_graceful_fail"

detect_language() {
    DEVICE_LOCALE="$(getprop persist.sys.locale)"
    [ -n "$DEVICE_LOCALE" ] || DEVICE_LOCALE="$(getprop ro.product.locale)"
    case "$DEVICE_LOCALE" in
        ru*|RU*|*_RU*|*-RU*) UI_LANG=ru ;;
        *) UI_LANG=en ;;
    esac
}

rotate_event_log() {
    SIZE="$(wc -c < "$EVENT_LOG" 2>/dev/null)"
    case "$SIZE" in
        ''|*[!0-9]*) SIZE=0 ;;
    esac
    if [ "$SIZE" -gt 262144 ]; then
        mv -f "$EVENT_LOG" "$EVENT_LOG.1"
    fi
}

save_pstore() {
    NEW_WLAN_PANIC=0
    for SRC in /sys/fs/pstore/console-ramoops-*; do
        [ -f "$SRC" ] || continue
        HASH="$(sha256sum "$SRC" 2>/dev/null | awk '{print $1}')"
        [ -n "$HASH" ] || continue
        DEST="$LOGROOT/console-ramoops-$HASH.txt"
        if [ ! -f "$DEST" ]; then
            cp -f "$SRC" "$DEST" 2>/dev/null
            chmod 0600 "$DEST" 2>/dev/null
            if grep -aEq 'WLAN Panic|MHI_DEV_SYS_ERR|Driver reinit failed' "$DEST"; then
                NEW_WLAN_PANIC=1
            fi
        fi
    done

    ls -1t "$LOGROOT"/console-ramoops-*.txt 2>/dev/null |
    tail -n +6 |
    while IFS= read -r OLD; do
        rm -f "$OLD"
    done
}

wait_for_android() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 2
    done
}

publish_logs() {
    wait_for_android
    mkdir -p "$PUBLIC_LOGROOT" 2>/dev/null || return
    cp -f "$LOGROOT"/console-ramoops-*.txt "$PUBLIC_LOGROOT"/ 2>/dev/null
    cp -f "$LOGROOT"/events.log* "$PUBLIC_LOGROOT"/ 2>/dev/null
    cp -f "$LOGROOT"/kernel.log* "$PUBLIC_LOGROOT"/ 2>/dev/null
    ls -1t "$PUBLIC_LOGROOT"/console-ramoops-*.txt 2>/dev/null |
    tail -n +6 |
    while IFS= read -r OLD; do
        rm -f "$OLD"
    done
    chmod 0755 "$PUBLIC_LOGROOT" 2>/dev/null
    chmod 0644 "$PUBLIC_LOGROOT"/* 2>/dev/null
}

notify_failure() {
    wait_for_android
    publish_logs
    detect_language
    if [ "$UI_LANG" = "ru" ]; then
        TITLE="Ошибка Wi-Fi"
        BODY="Модуль Wi-Fi не восстановился. Телефон продолжит работать; перезагрузите его, когда будет удобно."
    else
        TITLE="Wi-Fi failure"
        BODY="The Wi-Fi subsystem did not recover. The phone will keep running; reboot it when convenient."
    fi
    cmd notification post -t "$TITLE" wlan_recovery_failed "$BODY" >/dev/null 2>&1
}

notify_previous_panic() {
    wait_for_android
    publish_logs
    detect_language
    if [ "$UI_LANG" = "ru" ]; then
        TITLE="Сохранён журнал перезагрузки"
        BODY="Предыдущая перезагрузка связана с WPSS/Wi-Fi. Журнал: Внутренняя память/log/wlan_graceful_fail"
    else
        TITLE="Reboot log saved"
        BODY="The previous reboot was related to WPSS/Wi-Fi. Log: Internal storage/log/wlan_graceful_fail"
    fi
    cmd notification post -t "$TITLE" wlan_previous_panic "$BODY" >/dev/null 2>&1
}

rm -f "$STATE_FILE"
mkdir -p "$LOGROOT"
chmod 0700 "$LOGROOT"

save_pstore
publish_logs &
if [ "$NEW_WLAN_PANIC" = "1" ]; then
    notify_previous_panic &
fi

# Keep at most about 2 MiB of the current kernel log plus rotated files.
/system/bin/logcat -b kernel -v threadtime \
    -f "$LOGROOT/kernel.log" -r 512 -n 4 >/dev/null 2>&1 &

while true; do
    /system/bin/logcat -b kernel -v brief -T 1 2>/dev/null |
    while IFS= read -r LINE; do
        case "$LINE" in
            *"MHI_DEV_SYS_ERR"*|*"Received early crash indication from FW"*)
                rotate_event_log
                {
                    date
                    echo "$LINE"
                } >> "$EVENT_LOG"
                ;;
            *"consecutive reinit failures:"*|*"Driver reinit failed:"*)
                rotate_event_log
                {
                    date
                    echo "$LINE"
                } >> "$EVENT_LOG"
                if [ ! -e "$STATE_FILE" ]; then
                    : > "$STATE_FILE"
                    notify_failure &
                fi
                ;;
        esac
    done
    sleep 2
done

