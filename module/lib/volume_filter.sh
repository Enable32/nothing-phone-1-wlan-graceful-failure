#!/system/bin/sh

# A line-reading shell loop avoids the input buffering of some Android awk
# builds on a long-lived getevent pipe. Releases/repeats are not presses.
while IFS= read -r KEY_RAW; do
    case "$KEY_RAW" in
        *EV_KEY*KEY_VOLUMEUP*DOWN*|*"0001 0073 00000001"*) printf 'UP\n' ;;
        *EV_KEY*KEY_VOLUMEDOWN*DOWN*|*"0001 0072 00000001"*) printf 'DOWN\n' ;;
    esac
done
