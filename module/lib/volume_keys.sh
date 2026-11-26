#!/system/bin/sh

# Source from Action or the manual recovery entry point. No key grabs: input
# remains available to Android. Only volume-key presses are retained privately.
KEY_DIR=
KEY_READER_PID=
KEY_FILTER_PID=
KEY_LINE=0
KEY_EVENT=

key_clock() {
    read -r KEY_UPTIME _KEY_REST < /proc/uptime || return 1
    KEY_CLOCK=${KEY_UPTIME%%.*}
    case "$KEY_CLOCK" in ''|*[!0-9]*) return 1 ;; esac
}

keys_stop() {
    [ -z "$KEY_READER_PID" ] || kill "$KEY_READER_PID" 2>/dev/null
    [ -z "$KEY_FILTER_PID" ] || kill "$KEY_FILTER_PID" 2>/dev/null
    [ -z "$KEY_READER_PID" ] || wait "$KEY_READER_PID" 2>/dev/null
    [ -z "$KEY_FILTER_PID" ] || wait "$KEY_FILTER_PID" 2>/dev/null
    KEY_READER_PID=
    KEY_FILTER_PID=
    [ -z "$KEY_DIR" ] || rm -rf "$KEY_DIR"
    KEY_DIR=
    return 0
}

keys_start() {
    KEY_GETEVENT=$(command -v getevent 2>/dev/null) || return 1
    [ -r "$MODDIR/lib/volume_filter.sh" ] || return 1
    mkdir -p "$LOGROOT" || return 1
    KEY_DIR=$(mktemp -d "$LOGROOT/action_keys.XXXXXX") || return 1
    chmod 0700 "$KEY_DIR"
    KEY_LINE=0
    : > "$KEY_DIR/events"
    mkfifo "$KEY_DIR/input" || { keys_stop; return 1; }
    sh "$MODDIR/lib/volume_filter.sh" < "$KEY_DIR/input" \
        >> "$KEY_DIR/events" 2> "$KEY_DIR/filter-error" &
    KEY_FILTER_PID=$!
    "$KEY_GETEVENT" -ql > "$KEY_DIR/input" 2> "$KEY_DIR/input-error" &
    KEY_READER_PID=$!
    return 0
}

# 0 = one complete press in KEY_EVENT, 1 = no press yet, 2 = reader failed.
keys_poll() {
    KEY_EVENT=
    [ -n "$KEY_DIR" ] || return 2
    KEY_NEXT=$((KEY_LINE + 1))
    KEY_EVENT=$(sed -n "${KEY_NEXT}p" "$KEY_DIR/events" 2>/dev/null)
    case "$KEY_EVENT" in
        UP|DOWN) KEY_LINE=$KEY_NEXT; return 0 ;;
    esac
    kill -0 "$KEY_READER_PID" 2>/dev/null || return 2
    kill -0 "$KEY_FILTER_PID" 2>/dev/null || return 2
    return 1
}
