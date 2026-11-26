#!/system/bin/sh

# Userspace recovery only. This file never unloads a driver, writes a sysfs
# policy, flashes boot, toggles mobile data or restarts Bluetooth/system_server.
REC_MAX_ATTEMPTS=3
REC_TOTAL_SECONDS=180
REC_LOGROOT=/sdcard/log
REC_WORK=
REC_LOCK_OWNED=0
REC_LOG=
REC_OUTCOME=not_started

rec_clock() {
    read -r REC_NOW _REC_REST < /proc/uptime || return 1
    case "$REC_NOW" in ''|*[!0-9.]*) return 1 ;; esac
    REC_SECOND=${REC_NOW%%.*}
}

rec_log() { [ -z "$REC_LOG" ] || printf '%s\n' "$*" >> "$REC_LOG"; }
rec_say() {
    if [ "$RU" = 1 ]; then REC_MESSAGE=$1; else REC_MESSAGE=$2; fi
    printf '%s\n' "$REC_MESSAGE"
    rec_log "$REC_MESSAGE"
}

rec_cleanup() {
    if [ "$REC_LOCK_OWNED" = 1 ]; then
        # Never delete a different invocation's lock.
        if [ "$(cat "$LOGROOT/wifi_recovery.lock/pid" 2>/dev/null)" = "$$" ]; then
            rm -f "$LOGROOT/wifi_recovery.lock/pid"
            rmdir "$LOGROOT/wifi_recovery.lock" 2>/dev/null
        fi
    fi
    REC_LOCK_OWNED=0
    [ -z "$REC_WORK" ] || rm -rf "$REC_WORK"
    REC_WORK=
    return 0
}

rec_cancelled() {
    # The confirmation press was already consumed by Action. No raw getevent
    # data or user input is interpreted as a shell command.
    keys_poll
    REC_KEY_RC=$?
    case "$REC_KEY_RC:$KEY_EVENT" in
        0:DOWN) REC_OUTCOME=cancelled; return 0 ;;
        2:*) REC_OUTCOME=key_reader_lost; return 0 ;;
    esac
    return 1
}

rec_budget() {
    rec_clock || { REC_OUTCOME=clock_failed; return 1; }
    if [ "$REC_SECOND" -ge "$REC_DEADLINE" ]; then
        REC_OUTCOME=time_limit
        return 1
    fi
    return 0
}

rec_guard() {
    REC_POLICY=$(cat "$REC_WPSS/restart_level" 2>/dev/null)
    [ "$REC_POLICY" = RELATED ] || {
        rec_log "guard: WPSS restart_level=$REC_POLICY (RELATED required)"
        REC_OUTCOME=policy_not_related
        return 1
    }
    return 0
}

# Every Binder command has its own timeout, also capped by the total deadline.
# Return codes and text errors are both checked: some vendor cmd implementations
# print FAILED_TRANSACTION while returning zero.
rec_command() {
    rec_cancelled && return 130
    rec_budget || return 124
    REC_TIMEOUT=$((REC_DEADLINE - REC_SECOND))
    [ "$REC_TIMEOUT" -le 8 ] || REC_TIMEOUT=8
    rec_log "--- elapsed=$((REC_SECOND - REC_STARTED)) command: $*"
    timeout -k 1 "$REC_TIMEOUT" "$@" > "$REC_WORK/command" 2>&1
    REC_COMMAND_RC=$?
    tail -c 16384 "$REC_WORK/command" >> "$REC_LOG"
    rec_log "command_rc=$REC_COMMAND_RC"
    if [ "$REC_COMMAND_RC" -ne 0 ]; then
        REC_OUTCOME=command_failed
        return 1
    fi
    if grep -Eiq 'FAILED_TRANSACTION|Unknown command|SecurityException|Permission denied|Permission Denial|(^|[[:space:]])(Error:|Exception:|error:)|Can.t find service|not supported' "$REC_WORK/command"; then
        REC_OUTCOME=command_failed
        return 1
    fi
    return 0
}

rec_status() {
    rec_command cmd wifi status || return 1
    REC_ENABLED=0
    REC_CONNECTED=0
    grep -Eq '^Wifi is enabled[[:space:]]*$' "$REC_WORK/command" && REC_ENABLED=1
    if grep -Eq '^Wifi is connected to .+' "$REC_WORK/command" &&
            ip link show wlan0 2>/dev/null | grep -q LOWER_UP; then
        REC_CONNECTED=1
    fi
    if ! grep -Eq '^Wifi is (enabled|disabled)[[:space:]]*$' "$REC_WORK/command"; then
        REC_OUTCOME=unsupported_status_format
        return 1
    fi
    return 0
}

rec_pause() {
    REC_PAUSE_LEFT=$1
    while [ "$REC_PAUSE_LEFT" -gt 0 ]; do
        rec_cancelled && return 1
        rec_budget || return 1
        sleep 1
        REC_PAUSE_LEFT=$((REC_PAUSE_LEFT - 1))
    done
    return 0
}

rec_scan() {
    rec_command cmd wifi start-scan || return 1
    rec_clock || { REC_OUTCOME=clock_failed; return 1; }
    REC_LAST_SCAN=$REC_SECOND
}

# 0 = connected or demonstrably fresh APs, 1 = no success within this window,
# 2 = cancellation/command/guard error; caller must not send another restart.
rec_wait() {
    rec_clock || { REC_OUTCOME=clock_failed; return 2; }
    REC_SCAN_MARK=$REC_NOW
    REC_WINDOW_END=$((REC_SECOND + $1))
    rec_scan || return 2
    while :; do
        rec_pause 2 || return 2
        rec_guard || return 2
        rec_status || return 2
        if [ "$REC_CONNECTED" = 1 ]; then
            REC_OUTCOME=connected
            return 0
        fi
        rec_clock || { REC_OUTCOME=clock_failed; return 2; }
        REC_SNAPSHOT_NOW=$REC_NOW
        rec_command cmd wifi list-scan-results || return 2
        REC_SCAN_WINDOW=$(awk -v now="$REC_SNAPSHOT_NOW" -v mark="$REC_SCAN_MARK" 'BEGIN { printf "%.3f", now-mark }')
        REC_FRESH=$(awk -v window="$REC_SCAN_WINDOW" -f "$MODDIR/lib/fresh_scans.awk" "$REC_WORK/command")
        rec_log "fresh_results=$REC_FRESH window=$REC_SCAN_WINDOW"
        case "$REC_FRESH" in ''|*[!0-9]*) REC_OUTCOME=scan_parser_failed; return 2 ;; esac
        if [ "$REC_ENABLED" = 1 ] && [ "$REC_FRESH" -gt 0 ]; then
            REC_OUTCOME=fresh_networks
            return 0
        fi
        rec_clock || { REC_OUTCOME=clock_failed; return 2; }
        [ "$REC_SECOND" -lt "$REC_WINDOW_END" ] || return 1
        # Request another scan after initialization has had time to finish.
        if [ $((REC_SECOND - REC_LAST_SCAN)) -ge 10 ]; then
            rec_scan || return 2
        fi
    done
}

rec_preflight() {
    [ "$(id -u)" = 0 ] || { REC_OUTCOME=root_required; return 1; }
    [ "$(getprop ro.build.version.incremental)" = 2509261631 ] &&
        [ "$(uname -r)" = 5.4.274-qgki-g4670d6bdb795 ] || {
        REC_OUTCOME=unsupported_build; return 1
    }
    case "$(getprop ro.product.device):$(getprop ro.product.vendor.device)" in
        *Spacewar*|*spacewar*) ;;
        *) REC_OUTCOME=unsupported_device; return 1 ;;
    esac
    [ "$(getprop sys.boot_completed)" = 1 ] || {
        REC_OUTCOME=android_not_ready; return 1
    }
    REC_WPSS=
    for REC_NODE in /sys/bus/msm_subsys/devices/*; do
        [ "$(cat "$REC_NODE/name" 2>/dev/null)" = wpss ] || continue
        REC_WPSS=$REC_NODE
        break
    done
    [ -n "$REC_WPSS" ] || { REC_OUTCOME=wpss_missing; return 1; }
    rec_guard || return 1
    REC_BUILD_ID=$(od -An -tx1 -j16 -N8 /sys/module/wlan/notes/.note.gnu.build-id 2>/dev/null | tr -d '[:space:]')
    rec_log "loaded_wlan_build_id=$REC_BUILD_ID policy=$REC_POLICY"
    [ "$REC_BUILD_ID" = e2388611edd9fe47 ] || {
        REC_OUTCOME=early_v13_required; return 1
    }
    rec_command cmd wifi help || return 1
    for REC_CAPABILITY in trigger-recovery start-scan list-scan-results status set-wifi-enabled; do
        grep -Eq "^[[:space:]]*$REC_CAPABILITY([[:space:]]|$)" "$REC_WORK/command" || {
            REC_OUTCOME=unsupported_wifi_commands; return 1
        }
    done
    return 0
}

rec_loop() {
    rec_preflight || return 1
    rec_status || return 1
    if [ "$REC_CONNECTED" = 1 ]; then
        REC_OUTCOME=already_connected
        return 0
    fi
    if [ "$REC_ENABLED" != 1 ]; then
        rec_say "Запрашиваю включение Wi-Fi." "Requesting Wi-Fi enabled."
        rec_command cmd wifi set-wifi-enabled enabled || return 1
        rec_pause 4 || return 1
    fi
    rec_say "Сначала проверяю сканирование без перезапуска." "Checking scanning before any restart."
    rec_wait 10
    REC_WAIT_RC=$?
    [ "$REC_WAIT_RC" -ne 0 ] || return 0
    [ "$REC_WAIT_RC" -eq 1 ] || return 1
    REC_ATTEMPT=0
    while [ "$REC_ATTEMPT" -lt "$REC_MAX_ATTEMPTS" ]; do
        rec_cancelled && return 1
        rec_budget || return 1
        rec_guard || return 1
        REC_ATTEMPT=$((REC_ATTEMPT + 1))
        rec_say "Восстановление Wi-Fi: попытка $REC_ATTEMPT из $REC_MAX_ATTEMPTS. Громкость -: отмена." \
            "Wi-Fi recovery: attempt $REC_ATTEMPT of $REC_MAX_ATTEMPTS. Volume Down: cancel."
        rec_command cmd wifi trigger-recovery || return 1
        rec_pause 5 || return 1
        rec_wait 35
        REC_WAIT_RC=$?
        [ "$REC_WAIT_RC" -ne 0 ] || return 0
        [ "$REC_WAIT_RC" -eq 1 ] || return 1
    done
    REC_OUTCOME=attempt_limit
    return 1
}

recover_wifi() {
    REC_OUTCOME=not_started
    REC_ATTEMPT=0
    REC_LOG=
    REC_WORK=
    REC_LOCK_OWNED=0
    umask 077
    mkdir -p "$LOGROOT" "$REC_LOGROOT" || return 1
    if ! mkdir "$LOGROOT/wifi_recovery.lock" 2>/dev/null; then
        rec_say "Восстановление уже запущено или остался его lock. Повторная попытка отменена." \
            "Recovery is running or its lock remains. A second run was cancelled."
        return 1
    fi
    echo "$$" > "$LOGROOT/wifi_recovery.lock/pid" || {
        rmdir "$LOGROOT/wifi_recovery.lock" 2>/dev/null
        return 1
    }
    REC_LOCK_OWNED=1
    # BusyBox mktemp requires the Xs at the end of a template. Use a dated,
    # PID-qualified report and noclobber instead of a nonportable .txt suffix.
    REC_LOG="$REC_LOGROOT/wifi_recovery_$(date +%Y-%m-%d_%H-%M-%S)_$$.txt"
    (set -C; : > "$REC_LOG") 2>/dev/null || {
        echo "Could not create a new recovery log: $REC_LOG" >&2
        REC_LOG=
        rec_cleanup; return 1
    }
    REC_WORK=$(mktemp -d "$LOGROOT/wifi_recovery.XXXXXX") || {
        rec_cleanup; return 1
    }
    rec_clock || { rec_cleanup; return 1; }
    REC_STARTED=$REC_SECOND
    REC_DEADLINE=$((REC_STARTED + REC_TOTAL_SECONDS))
    rec_log "=== Manual WLAN userspace recovery v1.4 TEST ==="
    rec_log "$(date) max_attempts=$REC_MAX_ATTEMPTS deadline_seconds=$REC_TOTAL_SECONDS"
    rec_say "Wi-Fi и точка доступа могут временно отключиться. Громкость -: остановить попытки." \
        "Wi-Fi and hotspot may disconnect briefly. Volume Down stops further attempts."
    command -v timeout >/dev/null 2>&1 || REC_OUTCOME=timeout_tool_missing
    if [ "$REC_OUTCOME" = timeout_tool_missing ]; then
        REC_RESULT=1
    else
        rec_loop
        REC_RESULT=$?
    fi
    case "$REC_OUTCOME" in
        fresh_networks)
            rec_say "Появились свежие результаты сканирования. Перезапуски остановлены." \
                "Fresh scan results appeared. No more restarts will be requested." ;;
        connected|already_connected)
            rec_say "Android сообщает о подключении Wi-Fi, wlan0 активен. Перезапуски остановлены." \
                "Android reports Wi-Fi connected and wlan0 active. No more restarts requested." ;;
        cancelled)
            rec_say "Отменено. Новых перезапусков Wi-Fi не будет." \
                "Cancelled. No further Wi-Fi restarts will be requested." ;;
        attempt_limit|time_limit)
            rec_say "Лимит достигнут. Свежих сетей пока нет; дальнейшие попытки остановлены." \
                "Limit reached without fresh networks. Further attempts were stopped." ;;
        *)
            rec_say "Восстановление остановлено: $REC_OUTCOME. Подробности в журнале." \
                "Recovery stopped: $REC_OUTCOME. See the log for details." ;;
    esac
    rec_log "result=$REC_OUTCOME attempts=$REC_ATTEMPT exit=$REC_RESULT"
    # Keep a bounded copy for the existing one-archive diagnostic action.
    tail -c 524288 "$REC_LOG" > "$LOGROOT/wifi_recovery.log"
    chmod 0644 "$REC_LOG" 2>/dev/null
    echo "Log: $REC_LOG"
    rec_cleanup
    return "$REC_RESULT"
}
