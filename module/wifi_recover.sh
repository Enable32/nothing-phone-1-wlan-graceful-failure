#!/system/bin/sh

MODDIR=${0%/*}
LOGROOT=/data/adb/wlan_graceful_fail_logs
LOCALE=$(getprop persist.sys.locale)
[ -n "$LOCALE" ] || LOCALE=$(getprop ro.product.locale)
case "$LOCALE" in ru*|RU*) RU=1 ;; *) RU=0 ;; esac
. "$MODDIR/lib/volume_keys.sh"
. "$MODDIR/lib/wifi_recovery.sh"
trap 'rec_cleanup; keys_stop' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! keys_start; then
    echo "Volume-key input unavailable; recovery cancelled. Use Action to collect a dump."
    exit 1
fi
recover_wifi
exit $?
