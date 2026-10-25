#!/bin/sh
# platform: macOS-only -- links and runs x86_64 Mach-O against a dylib built from librecaulk.a's members
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macos.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
D="$(mktemp -d "${TMPDIR:-/tmp}/forward-dylib.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
field() { printf '%s\n' "$1" | sed -n "s/^$2: //p"; }
names="os_system_version_get_current_version qos_class_self"

ver="$(macos_version)"
case "$ver" in
  *.*.*) ver3="$ver" ;;
  *) ver3="$ver.0" ;;
esac
if ! version_below "$ver" 10.12; then
  era=system
elif version_below "$ver" 10.10 && ! version_below "$ver" 10.9; then
  era=10.9
else
  era=between
fi
echo "era: $era ($ver)"

nm -A "$T/lib/librecaulk.a" > "$D/archive.nm" || { echo "FAIL: nm -A could not read librecaulk.a"; exit 1; }
want="___recaulk_resolve"
for n in $names; do want="$want _$n ___recaulk_impl_$n"; done
mkdir "$D/members"
for s in $want; do
  m="$(awk -v s="$s" '$NF == s && $(NF-1) == "T" { sub(/^.*\.a:/, "", $1); sub(/:$/, "", $1); print $1 }' "$D/archive.nm")"
  [ "$(printf '%s\n' "$m" | grep -c .)" = 1 ] || { echo "FAIL: librecaulk.a defines $s in ${m:-no member} (want exactly one)"; exit 1; }
  (cd "$D/members" && ar -x "$T/lib/librecaulk.a" "$m")
done
ar rcs "$D/librecaulk-subset.a" "$D"/members/*.o
echo "subset archive: $(cd "$D/members" && ls | tr '\n' ' ')"

hide_api=""
for n in $names; do hide_api="$hide_api -Wl,-unexported_symbol,_$n"; done
for shape in hidden exported; do
  lib="$D/libforward-$shape.dylib"
  extra=""
  [ "$shape" = exported ] || extra="$hide_api"
  /usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" -dynamiclib \
    -install_name "$lib" -o "$lib" tests/c/forward_dylib.c "$D/librecaulk-subset.a" \
    -Wl,-unexported_symbol,'___recaulk_*' $extra \
    || { echo "FAIL: a dylib calling $names does not link from librecaulk.a's members alone"; exit 1; }
  nm -gU "$lib" | awk '{ print $NF }' | LC_ALL=C sort > "$D/$shape.exports"
  case "$shape" in
    hidden) printf '%s\n' _forward_dylib_probe ;;
    exported) printf '%s\n' _forward_dylib_probe _os_system_version_get_current_version _qos_class_self ;;
  esac | LC_ALL=C sort > "$D/$shape.want"
  cmp -s "$D/$shape.exports" "$D/$shape.want" \
    || bad "the $shape dylib exports $(tr '\n' ' ' < "$D/$shape.exports")but should export only $(tr '\n' ' ' < "$D/$shape.want")(no ___recaulk_ name, and an API name only where the link leaves it exported)"
  for n in $names; do
    nm -u "$lib" | awk "{ print \$NF }" | grep -qx "_$n" && bad "the $shape dylib imports _$n instead of carrying Recaulk's trampoline"
    nm "$lib" | awk -v s="_$n" '$NF == s && ($2 == "t" || $2 == "T") { f = 1 } END { exit !f }' \
      || bad "the $shape dylib does not define _$n"
  done
done

/usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" -o "$D/main-dlopen" tests/c/forward_dylib_main.c \
  || { echo "FAIL: the dlopen test program does not link"; exit 1; }
for shape in hidden exported; do
  lib="$D/libforward-$shape.dylib"
  /usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -DLINKED -isystem "$T/include/recaulk" -o "$D/main-$shape-system-first" \
    tests/c/forward_dylib_main.c -lSystem -lobjc "$lib" \
    || { echo "FAIL: a program listing libSystem and libobjc before the $shape dylib does not link"; exit 1; }
  /usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -DLINKED -isystem "$T/include/recaulk" -o "$D/main-$shape-dylib-first" \
    tests/c/forward_dylib_main.c "$lib" -lobjc \
    || { echo "FAIL: a program listing the $shape dylib before libobjc and libSystem does not link"; exit 1; }
done

order() { otool -L "$1" | awk 'NR > 1 { sub(/.*\//, "", $1); printf "%s ", $1 }'; }
for prog in "$D"/main-*; do
  nm "$prog" | grep -q '___recaulk_' && bad "$(basename "$prog") carries Recaulk symbols itself, so it does not prove the dylib's forwarding"
done
first="$(order "$D/main-hidden-system-first")"
case "$first" in
  libSystem.B.dylib\ libobjc.A.dylib\ libforward-hidden.dylib\ *) ;;
  *) bad "main-hidden-system-first loads $first, want libSystem, libobjc, then the dylib" ;;
esac
first="$(order "$D/main-hidden-dylib-first")"
case "$first" in
  libforward-hidden.dylib\ *) ;;
  *) bad "main-hidden-dylib-first loads $first, want the dylib first" ;;
esac

bounded() {
  "$@" > "$D/out" 2>&1 &
  bpid=$!
  ( sleep 60 & spid=$!; trap "kill \$spid; exit 0" TERM; wait "$spid"; kill -9 "$bpid" ) > /dev/null 2>&1 &
  wpid=$!
  wait "$bpid" && brc=0 || brc=$?
  { kill "$wpid"; wait "$wpid"; } > /dev/null 2>&1 || true
  return $brc
}

judge() {
  label="$1"; shape="$2"; order="$3"; out="$4"
  self="$(field "$out" self)"
  [ "$self" = "$D/libforward-$shape.dylib" ] || { bad "$label: the probe ran from ${self:-nowhere}, not the dylib"; return; }
  for n in osv qos; do
    [ "$(field "$out" "$n-slot-before")" = "(none)" ] \
      || bad "$label: the dylib's $n slot was already resolved before its first call, so the dylib was not the first to reach the forwarding layer"
    nxt="$(field "$out" "next-$n")"
    [ "$nxt" != "$self" ] || bad "$label: dlsym(RTLD_NEXT) from inside the dylib found the dylib's own $n: a resolver would forward to itself"
  done
  case "$(field "$out" next-getpid)" in
    /usr/lib/*) ;;
    *) bad "$label: dlsym(RTLD_NEXT, \"getpid\") from inside the dylib found $(field "$out" next-getpid), not libSystem's: RTLD_NEXT does not reach the system from this dylib" ;;
  esac
  [ "$(field "$out" osv-rc)" = 0 ] || bad "$label: os_system_version_get_current_version returned $(field "$out" osv-rc), want 0"
  case "$era" in
    10.9)
      [ "$(field "$out" osv-version)" = "$ver3" ] || bad "$label: os_system_version_get_current_version reported $(field "$out" osv-version), want $ver3 (sw_vers)"
      [ "$(field "$out" qos)" = 0 ] || bad "$label: qos_class_self returned $(field "$out" qos), want QOS_CLASS_UNSPECIFIED (0)"
      for n in osv qos; do
        [ "$(field "$out" "$n-target")" = "$self" ] || bad "$label: on $ver the $n slot resolved to $(field "$out" "$n-target"), want the back-fill in $self"
        [ "$(field "$out" "next-$n")" = "(none)" ] || bad "$label: on $ver dlsym(RTLD_NEXT) found a system $n in $(field "$out" "next-$n"); the forwarded set assumes 10.9 has none"
      done
      if [ "$shape" = exported ] && [ "$order" = dylib-first ]; then
        [ "$(field "$out" default-qos)" = "$self" ] \
          || bad "$label: control: dlsym(RTLD_DEFAULT, \"qos_class_self\") found $(field "$out" default-qos), not the dylib's own exported trampoline, so this test cannot show a resolver that would self-resolve"
      fi ;;
    system)
      osv_sys="$(field "$out" system-osv | sed "s/^0 //")"
      if [ "$(field "$out" osv-version)" = "$osv_sys" ]; then
        echo "$label: on $ver os_system_version_get_current_version from the dylib reported $osv_sys, as the system's does"
      else
        bad "$label: the dylib's os_system_version_get_current_version reported $(field "$out" osv-version), the system's $(field "$out" system-osv)"
      fi
      if [ "$(field "$out" qos)" = "$(field "$out" system-qos)" ]; then
        echo "$label: on $ver qos_class_self from the dylib returned $(field "$out" qos), as the system's does"
      else
        bad "$label: the dylib's qos_class_self returned $(field "$out" qos), the system's $(field "$out" system-qos)"
      fi
      echo "$label: on $ver RTLD_NEXT from the dylib found osv in $(field "$out" next-osv), qos in $(field "$out" next-qos), getpid in $(field "$out" next-getpid)"
      for n in osv qos; do
        tgt="$(field "$out" "$n-target")"
        case "$tgt" in
          "$self") bad "$label: on $ver the $n slot resolved to the dylib itself: forwarding from a dylib must reach the system's implementation" ;;
          /usr/lib/*|/System/*) echo "$label: on $ver $n forwarded to $tgt" ;;
          *) bad "$label: on $ver the $n slot resolved to $tgt, not the system's: a back-fill must defer to the system's implementation when it exists (spec, Product 1)" ;;
        esac
      done
      echo "$label: diagnostic: dlsym(RTLD_DEFAULT, \"qos_class_self\") found $(field "$out" default-qos)" ;;
    *) echo "$label: on $ver osv ran $(field "$out" osv-target), qos ran $(field "$out" qos-target) (no assertion between 10.9 and 10.12)" ;;
  esac
}

for shape in hidden exported; do
  for order in system-first dylib-first dlopen; do
    label="$shape dylib, $order"
    if [ "$order" = dlopen ]; then
      set -- "$D/main-dlopen" "$D/libforward-$shape.dylib"
    else
      set -- "$D/main-$shape-$order"
    fi
    bounded "$@" && rc=0 || rc=$?
    out="$(cat "$D/out")"
    printf '%s\n' "--- $label" "$out"
    [ "$rc" = 0 ] || { bad "$label: the program exited $rc (137 is the 60s watchdog: a slot that resolved to its own trampoline loops forever)"; continue; }
    judge "$label" "$shape" "$order" "$out"
  done
done

[ "$fail" = 0 ] && echo "forward-dylib OK"
exit $fail
