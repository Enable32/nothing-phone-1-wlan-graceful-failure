#!/system/bin/sh

MODDIR=${0%/*}
LOGROOT="/data/adb/wlan_graceful_fail_logs"
PUBLIC_LOGROOT="/sdcard/log"

LOCALE="$(getprop persist.sys.locale)"
[ -n "$LOCALE" ] || LOCALE="$(getprop ro.product.locale)"
case "$LOCALE" in
    ru*|RU*) RU=1 ;;
    *) RU=0 ;;
esac

mkdir -p "$LOGROOT" "$PUBLIC_LOGROOT" 2>/dev/null

read_uptime() {
    read -r UP_RAW _REST < /proc/uptime 2>/dev/null
    UP_SECONDS=${UP_RAW%%.*}
    case "$UP_SECONDS" in
        ''|*[!0-9]*) UP_SECONDS=0 ;;
    esac
    UP_DAYS=$((UP_SECONDS / 86400))
    UP_HOURS=$(((UP_SECONDS % 86400) / 3600))
    UP_MINUTES=$(((UP_SECONDS % 3600) / 60))
}

show_uptime() {
    read_uptime
    echo
    if [ "$RU" = "1" ]; then
        echo "Время работы: $UP_DAYS дн. $UP_HOURS ч. $UP_MINUTES мин."
        echo "Всего секунд: $UP_SECONDS"
    else
        echo "Uptime: $UP_DAYS d $UP_HOURS h $UP_MINUTES min"
        echo "Total seconds: $UP_SECONDS"
    fi
}

write_status() {
    read_uptime
    echo "=== TIME ==="
    date
    echo "=== UPTIME ==="
    echo "seconds=$UP_SECONDS"
    echo "days=$UP_DAYS hours=$UP_HOURS minutes=$UP_MINUTES"
    echo "=== BOOT ID ==="
    cat /proc/sys/kernel/random/boot_id 2>&1
    echo "=== MODULE ==="
    cat "$MODDIR/module.prop" 2>&1
    echo "=== BUILD ==="
    getprop ro.product.device
    getprop ro.build.version.incremental
    uname -a
    echo "=== BOOT REASON ==="
    getprop ro.boot.bootreason
    getprop sys.boot.reason
    echo "=== MAGISK/SLOT ==="
    magisk -v 2>&1
    getprop ro.boot.slot_suffix
    echo "=== SSR PARAMETERS ==="
    for PARAM in /sys/module/subsystem_restart/parameters/*; do
        [ -f "$PARAM" ] || continue
        echo "--- $PARAM"
        cat "$PARAM" 2>&1
    done
    echo "=== HUNG TASK SETTINGS ==="
    for PARAM in hung_task_panic hung_task_timeout_secs panic_on_warn; do
        echo "--- $PARAM"
        cat "/proc/sys/kernel/$PARAM" 2>&1
    done
    echo "=== WPSS POLICY ==="
    for NODE in /sys/bus/msm_subsys/devices/*; do
        [ -f "$NODE/name" ] || continue
        [ "$(cat "$NODE/name" 2>/dev/null)" = "wpss" ] || continue
        echo "node=$NODE"
        echo "restart_level=$(cat "$NODE/restart_level" 2>/dev/null)"
        for FIELD in state crash_count crash_reason crash_timestamp system_debug; do
            echo "$FIELD=$(cat "$NODE/$FIELD" 2>/dev/null)"
        done
    done
    echo "=== ACTIVE WLAN FILES ==="
    sha256sum /vendor/lib/modules/qca_cld3_wlan.ko 2>&1
    sha256sum /vendor/lib/modules/5.4-gki/qca_cld3_wlan.ko 2>&1
    sha256sum /vendor/lib/modules/qca_cld3_qca6750.ko 2>&1
    echo "=== LOADED MODULE ==="
    grep '^wlan ' /proc/modules 2>&1
    echo "=== LOADED WLAN BUILD ID ==="
    /system/bin/toybox od -An -tx1 -j16 -N8 \
        /sys/module/wlan/notes/.note.gnu.build-id 2>&1
    echo "expected_v13=e2388611edd9fe47"
    echo "=== WIFI INTERFACE ==="
    ip link show wlan0 2>&1
    echo "wifi_hal=$(getprop init.svc.vendor.wifi_hal_legacy)"
    echo "=== WLAN MOUNTS ==="
    grep -E 'qca_cld3_(wlan|qca6750)\.ko' /proc/mounts 2>&1
    echo "=== EARLY RESCUE MARKERS ==="
    dmesg 2>&1 | grep -a 'WPSS_RESCUE:' | tail -n 30
}

create_dump() {
    STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
    DUMP_NAME="wlan_dump_$STAMP"
    [ ! -e "$PUBLIC_LOGROOT/$DUMP_NAME.tar.gz" ] || DUMP_NAME="${DUMP_NAME}_$$"
    DUMP_DIR="$LOGROOT/$DUMP_NAME"
    ARCHIVE="$PUBLIC_LOGROOT/$DUMP_NAME.tar.gz"
    ARCHIVE_TMP="$ARCHIVE.partial"

    mkdir -p "$DUMP_DIR/pstore" "$DUMP_DIR/module_logs" "$DUMP_DIR/loader" || return 1
    write_status > "$DUMP_DIR/status.txt"

    cp -f /sys/fs/pstore/* "$DUMP_DIR/pstore/" 2>/dev/null
    cp -f "$LOGROOT"/console-ramoops-*.txt "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f "$LOGROOT"/pmsg-ramoops-*.txt "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f "$LOGROOT"/events.log* "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f "$LOGROOT"/kernel.log* "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f "$LOGROOT"/wifi_recovery.log "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f /data/adb/wpss_related_rescue.log "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f /sys/module/wlan/notes/.note.gnu.build-id \
        "$DUMP_DIR/loaded-wlan-build-id.bin" 2>/dev/null
    cp -f /vendor/bin/vendor_modprobe.sh "$DUMP_DIR/loader/" 2>/dev/null
    for FILE in modules.load modules.blocklist modules.dep modules.alias modules.softdep; do
        cp -f "/vendor/lib/modules/$FILE" "$DUMP_DIR/loader/" 2>/dev/null
    done

    dmesg 2>&1 | tail -c 2097152 > "$DUMP_DIR/dmesg_tail.txt"
    /system/bin/logcat -b kernel -d -v threadtime 2>&1 |
        tail -c 2097152 > "$DUMP_DIR/kernel_current.txt"

    TAR_BIN="$(command -v tar 2>/dev/null)"
    if [ -n "$TAR_BIN" ]; then
        "$TAR_BIN" -czf "$ARCHIVE_TMP" -C "$LOGROOT" "$DUMP_NAME"
        TAR_RESULT=$?
    elif [ -x /data/adb/magisk/busybox ]; then
        /data/adb/magisk/busybox tar -czf "$ARCHIVE_TMP" \
            -C "$LOGROOT" "$DUMP_NAME"
        TAR_RESULT=$?
    else
        TAR_RESULT=127
    fi

    if [ "$TAR_RESULT" = "0" ] && [ -s "$ARCHIVE_TMP" ] && mv -f "$ARCHIVE_TMP" "$ARCHIVE"; then
        rm -rf "$DUMP_DIR"
        chmod 0644 "$ARCHIVE" 2>/dev/null
        echo
        if [ "$RU" = "1" ]; then
            echo "Готов один архив с диагностикой:"
        else
            echo "One diagnostic archive was created:"
        fi
        echo "$ARCHIVE"
    else
        rm -f "$ARCHIVE_TMP"
        echo
        if [ "$RU" = "1" ]; then
            echo "Не удалось создать архив. Файлы оставлены в папке:"
        else
            echo "Could not create the archive. Files were kept in:"
        fi
        echo "$DUMP_DIR"
        return 1
    fi
}

# All menu operations share one key reader, including cancellation during recovery.
. "$MODDIR/lib/volume_keys.sh"
. "$MODDIR/lib/action_menu.sh"
. "$MODDIR/lib/wifi_recovery.sh"
trap 'rec_cleanup; keys_stop' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! keys_start; then
    if [ "$RU" = 1 ]; then
        echo "Кнопки недоступны. Создаю только диагностический архив."
    else
        echo "Volume keys unavailable. Creating only a diagnostic archive."
    fi
    create_dump
    exit $?
fi

choose_action
MENU_RESULT=$?
case "$MENU_RESULT" in
    0) ;;
    3)
        if [ "$RU" = 1 ]; then echo "Время выбора истекло. Действие отменено."
        else echo "Menu timed out. No action was started."; fi
        exit 0
        ;;
    *)
        if [ "$RU" = 1 ]; then echo "Ошибка чтения кнопок. Создаю только дамп."
        else echo "Key input failed. Creating only a dump."; fi
        create_dump
        exit $?
        ;;
esac

case "$ACTION_SELECTED" in
    1) keys_stop; show_uptime ;;
    2) keys_stop; create_dump ;;
    3) recover_wifi ;;
    4) keys_stop; sh "$MODDIR/boot_patch.sh" ;;
    5) exit 0 ;;
    *) exit 1 ;;
esac
