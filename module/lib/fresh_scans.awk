# Input: the real AOSP `cmd wifi list-scan-results` text table.
# Only a measured beacon newer than the scan request counts. An enabled switch,
# cached SSID, header or unknown timestamp cannot satisfy this check.
# window is measured BEFORE querying results; a margin makes the comparison
# conservative in the presence of command/clock rounding.
BEGIN { count = 0; limit = window - 0.25; if (limit > 5) limit = 5 }
{
    if (split($1, octets, ":") != 6) next
    valid = 1
    for (i = 1; i <= 6; i++) {
        if (octets[i] !~ /^[[:xdigit:]][[:xdigit:]]$/) valid = 0
    }
    if (!valid || $2 !~ /^[0-9]+$/) next
    row = $0
    sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+[0-9]+[[:space:]]+/, "", row)
    # RSSI can include a radio-chain field containing spaces, e.g. -9(0: -9).
    if (row !~ /^-?[0-9]+(\([^)]*\))?[[:space:]]+/) next
    sub(/^-?[0-9]+(\([^)]*\))?[[:space:]]+/, "", row)
    split(row, columns, /[[:space:]]+/)
    age = columns[1]
    gsub(/,/, ".", age)
    if (age !~ /^[0-9]+\.[0-9][0-9][0-9]$/) next
    if (limit >= 0 && age + 0 <= limit) count++
}
END { print count }
