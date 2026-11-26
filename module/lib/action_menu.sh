#!/system/bin/sh

menu_label() {
    case "$1:$RU" in
        1:1) echo "Время работы" ;;
        2:1) echo "Один архив диагностики" ;;
        3:1) echo "Восстановить Wi-Fi: до 3 попыток" ;;
        4:1) echo "Backup и отдельный TEST boot" ;;
        5:1) echo "Выход" ;;
        1:*) echo "Uptime" ;;
        2:*) echo "One diagnostic archive" ;;
        3:*) echo "Recover Wi-Fi: up to 3 attempts" ;;
        4:*) echo "Backup and separate TEST boot" ;;
        5:*) echo "Exit" ;;
    esac
}

choose_action() {
    ACTION_SELECTED=1
    echo
    if [ "$RU" = 1 ]; then
        echo "Громкость +: следующий номер. Громкость -: выполнить."
        echo "Без нажатий меню закроется через 120 секунд."
    else
        echo "Volume Up: next number. Volume Down: run selected action."
        echo "The menu times out after 120 seconds without a key press."
    fi
    MENU_NUMBER=1
    while [ "$MENU_NUMBER" -le 5 ]; do
        echo "  $MENU_NUMBER. $(menu_label "$MENU_NUMBER")"
        MENU_NUMBER=$((MENU_NUMBER + 1))
    done
    echo "> [$ACTION_SELECTED] $(menu_label "$ACTION_SELECTED")"
    key_clock || return 2
    MENU_DEADLINE=$((KEY_CLOCK + 120))
    while :; do
        key_clock || return 2
        [ "$KEY_CLOCK" -lt "$MENU_DEADLINE" ] || return 3
        keys_poll
        MENU_KEY_RC=$?
        case "$MENU_KEY_RC:$KEY_EVENT" in
            0:UP)
                ACTION_SELECTED=$((ACTION_SELECTED % 5 + 1))
                echo "> [$ACTION_SELECTED] $(menu_label "$ACTION_SELECTED")"
                MENU_DEADLINE=$((KEY_CLOCK + 120))
                ;;
            0:DOWN) return 0 ;;
            2:*) return 2 ;;
        esac
        sleep 0.15
    done
}
