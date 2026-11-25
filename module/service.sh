#!/system/bin/sh

MODDIR=${0%/*}
STATE_FILE="$MODDIR/.notified_this_boot"
LOGROOT="/data/adb/wlan_graceful_fail_logs"
EVENT_LOG="$LOGROOT/events.log"
PUBLIC_LOGROOT="/sdcard/log"

LOCALE="$(getprop persist.sys.locale)"
[ -n "$LOCALE" ] || LOCALE="$(getprop ro.product.locale)"
case "$LOCALE" in
    ru*|RU*)
        FAILURE_TITLE="Ошибка Wi-Fi"
        FAILURE_TEXT="WPSS/WLAN дал сбой. Тест v1.3 пытается восстановить Wi-Fi; результат нужно проверить. Для дампа: Action, Громкость -, затем Громкость +."
        PANIC_TITLE="Сохранён журнал перезагрузки"
        PANIC_TEXT="В журнале прошлой загрузки есть ошибки WPSS/Wi-Fi. Для дампа: Action, Громкость -, затем Громкость +."
        ;;
    *)
        FAILURE_TITLE="Wi-Fi failure"
        FAILURE_TEXT="WPSS/WLAN failed. The v1.3 test attempts Wi-Fi recovery; verify whether it succeeded. For a dump: Action, Volume Down, then Volume Up."
        PANIC_TITLE="Reboot log saved"
        PANIC_TEXT="The previous boot log contains WPSS/Wi-Fi errors. For a dump: Action, Volume Down, then Volume Up."
        ;;
esac

rm -f "$STATE_FILE"
mkdir -p "$LOGROOT"
chmod 0700 "$LOGROOT"

rotate_event_log() {
    SIZE="$(wc -c < "$EVENT_LOG" 2>/dev/null)"
    case "$SIZE" in
        ''|*[!0-9]*) SIZE=0 ;;
    esac
    if [ "$SIZE" -gt 262144 ]; then
        mv -f "$EVENT_LOG" "$EVENT_LOG.1"
    fi
}

record_boot_status() {
    rotate_event_log
    {
        echo "=== MODULE BOOT $(date) ==="
        echo "build=$(getprop ro.build.version.incremental)"
        echo "bootreason=$(getprop ro.boot.bootreason)"
        sha256sum /vendor/lib/modules/qca_cld3_wlan.ko 2>&1
        sha256sum /vendor/lib/modules/5.4-gki/qca_cld3_wlan.ko 2>&1
        sha256sum /vendor/lib/modules/qca_cld3_qca6750.ko 2>&1
        echo "loaded_wlan_build_id=$(/system/bin/toybox od -An -tx1 -j16 -N8 /sys/module/wlan/notes/.note.gnu.build-id 2>/dev/null | tr -d '[:space:]')"
        echo "expected_v13_build_id=e2388611edd9fe47"
        grep '^wlan ' /proc/modules 2>&1
        grep -E 'qca_cld3_(wlan|qca6750)\.ko' /proc/mounts 2>&1
        dmesg 2>&1 | grep -a 'WPSS_RESCUE:' | tail -n 30
    } >> "$EVENT_LOG"
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
            if grep -aEq 'WLAN Panic|MHI_DEV_SYS_ERR|Driver reinit failed|consecutive probe failures|QDF BUG in __hdd_soc_probe|Subsys notifier chain for wpss|wlan_hdd_pld_shutdown' "$DEST"; then
                NEW_WLAN_PANIC=1
            fi
        fi
    done

    for SRC in /sys/fs/pstore/pmsg-ramoops-*; do
        [ -f "$SRC" ] || continue
        HASH="$(sha256sum "$SRC" 2>/dev/null | awk '{print $1}')"
        [ -n "$HASH" ] || continue
        DEST="$LOGROOT/pmsg-ramoops-$HASH.txt"
        if [ ! -f "$DEST" ]; then
            cp -f "$SRC" "$DEST" 2>/dev/null
            chmod 0600 "$DEST" 2>/dev/null
        fi
    done

    ls -1t "$LOGROOT"/console-ramoops-*.txt 2>/dev/null |
    tail -n +6 |
    while IFS= read -r OLD; do
        rm -f "$OLD"
    done
    ls -1t "$LOGROOT"/pmsg-ramoops-*.txt 2>/dev/null |
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
    # /sdcard/log is shared with manual diagnostics. Do not delete its files.
    chmod 0755 "$PUBLIC_LOGROOT" 2>/dev/null
}

notify_failure() {
    wait_for_android
    publish_logs
    cmd notification post \
        -t "$FAILURE_TITLE" \
        wlan_recovery_failed \
        "$FAILURE_TEXT" \
        >/dev/null 2>&1
}

notify_previous_panic() {
    wait_for_android
    publish_logs
    cmd notification post \
        -t "$PANIC_TITLE" \
        wlan_previous_panic \
        "$PANIC_TEXT" \
        >/dev/null 2>&1
}

record_boot_status
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
                if [ ! -e "$STATE_FILE" ]; then
                    : > "$STATE_FILE"
                    notify_failure &
                fi
                ;;
            *"consecutive reinit failures:"*|*"consecutive probe failures:"*|*"Driver reinit failed:"*)
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
