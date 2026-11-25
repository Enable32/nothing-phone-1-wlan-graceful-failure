#!/system/bin/sh

LOG="/data/adb/wpss_related_rescue.log"
TAG="WPSS_RESCUE"

rotate_log() {
    SIZE="$(wc -c < "$LOG" 2>/dev/null)"
    case "$SIZE" in
        ''|*[!0-9]*) SIZE=0 ;;
    esac
    [ "$SIZE" -le 65536 ] || mv -f "$LOG" "$LOG.1"
}

record() {
    rotate_log
    echo "$(date) $*" >> "$LOG"
    echo "<6>$TAG: $*" > /dev/kmsg 2>/dev/null || true
}

TRIES=0
while [ "$TRIES" -lt 25 ]; do
    for NODE in /sys/bus/msm_subsys/devices/*; do
        [ -f "$NODE/name" ] || continue
        [ "$(cat "$NODE/name" 2>/dev/null)" = "wpss" ] || continue
        BEFORE="$(cat "$NODE/restart_level" 2>/dev/null)"
        [ "$BEFORE" = "RELATED" ] || echo RELATED > "$NODE/restart_level" 2>/dev/null
        AFTER="$(cat "$NODE/restart_level" 2>/dev/null)"
        record "post-fs-data node=$NODE before=$BEFORE after=$AFTER"
        [ "$AFTER" = "RELATED" ] && exit 0
    done
    TRIES=$((TRIES + 1))
    sleep 0.2
done

record "post-fs-data failed after $TRIES attempts"
exit 1
