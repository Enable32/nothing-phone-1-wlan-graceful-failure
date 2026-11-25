#!/system/bin/sh

MODE=${1:-once}
TRIGGER=${2:-unknown}
TAG=WPSS_RESCUE
LAST_STATE=
SCRIPT_DIR=${0%/*}
DRIVER_SOURCE="$SCRIPT_DIR/qca_cld3_qca6750.ko"
DRIVER_TARGET=/vendor/lib/modules/qca_cld3_qca6750.ko
EXPECTED_DRIVER_HASH=291cce1505c234e8425abf3eea385fe077ae8663ba1c1337c414b6d0be6b93e9

klog() {
  echo "<6>${TAG}: $*" > /dev/kmsg 2>/dev/null || true
}

early_mount_driver() {
  if [ ! -r "$DRIVER_SOURCE" ]; then
    klog "trigger=$TRIGGER early WLAN source missing: $DRIVER_SOURCE"
    return 1
  fi
  if [ ! -f "$DRIVER_TARGET" ]; then
    klog "trigger=$TRIGGER early WLAN target missing: $DRIVER_TARGET"
    return 1
  fi

  source_hash=$(sha256sum "$DRIVER_SOURCE" 2>/dev/null | awk '{print $1}')
  if [ "$source_hash" != "$EXPECTED_DRIVER_HASH" ]; then
    klog "trigger=$TRIGGER early WLAN source hash rejected: $source_hash"
    return 1
  fi

  chcon u:object_r:vendor_file:s0 "$DRIVER_SOURCE" 2>/dev/null || true
  mount -o bind "$DRIVER_SOURCE" "$DRIVER_TARGET" 2>/dev/null || {
    klog "trigger=$TRIGGER early WLAN bind mount failed"
    return 1
  }

  target_hash=$(sha256sum "$DRIVER_TARGET" 2>/dev/null | awk '{print $1}')
  if [ "$target_hash" != "$EXPECTED_DRIVER_HASH" ]; then
    klog "trigger=$TRIGGER early WLAN mounted hash rejected: $target_hash"
    umount "$DRIVER_TARGET" 2>/dev/null || true
    return 1
  fi

  klog "trigger=$TRIGGER early QCA6750 mounted before vendor_modprobe sha256=$target_hash expected_build_id=e2388611edd9fe47"
  return 0
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

case "$MODE" in
  early-mount)
    early_mount_driver
    exit $?
    ;;
  once)
    apply_related
    RC=$?
    [ "$RC" -eq 0 ] || klog "trigger=$TRIGGER one-shot failed rc=$RC"
    exit "$RC"
    ;;
esac

i=0
while [ "$i" -lt 450 ]; do
  apply_related
  i=$((i + 1))
  /system/bin/sleep 0.2
done

klog "trigger=$TRIGGER guard finished"
exit 0
