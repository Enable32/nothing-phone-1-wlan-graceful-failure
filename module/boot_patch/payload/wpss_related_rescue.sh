#!/system/bin/sh

MODE=${1:-once}
TRIGGER=${2:-unknown}
TAG=WPSS_RESCUE
LAST_STATE=

klog() {
  echo "<6>${TAG}: $*" > /dev/kmsg 2>/dev/null || true
}

apply_related() {
  found=0
  for node in /sys/bus/msm_subsys/devices/*; do
    [ -f "$node/name" ] || continue
    name=$(cat "$node/name" 2>/dev/null)
    [ "$name" = "wpss" ] || continue

    found=1
    level="$node/restart_level"
    before=$(cat "$level" 2>/dev/null)

    if [ "$before" != "RELATED" ]; then
      echo RELATED > "$level" 2>/dev/null || true
    fi

    after=$(cat "$level" 2>/dev/null)
    if [ "$after" != "$LAST_STATE" ] || [ "$MODE" = "once" ]; then
      klog "trigger=$TRIGGER node=$node before=$before after=$after"
      LAST_STATE=$after
    fi

    [ "$after" = "RELATED" ] && return 0
    return 1
  done

  [ "$found" -eq 1 ] && return 1
  return 2
}

if [ "$MODE" = "once" ]; then
  apply_related
  RC=$?
  [ "$RC" -eq 0 ] || klog "trigger=$TRIGGER one-shot failed rc=$RC"
  exit "$RC"
fi

i=0
while [ "$i" -lt 450 ]; do
  apply_related
  i=$((i + 1))
  /system/bin/sleep 0.2
done

klog "trigger=$TRIGGER guard finished"
exit 0
