#!/bin/sh
# platform: macOS-only -- Drydock's strict Objective-C analyzer (drydock-objc analyze) runs on macOS only; elsewhere this skips
# spec: README.md "Objective-C methods" -- objc-providers.json is schema 2, and Recaulk's pinned Drydock (0.7.1 or
#       later) credits each group (the class methods, and NSView's and NSCell's accessibility) whole: a consumer
#       linked as `drydock-objc link-args` says, with build evidence, has every member's send provided and every group
#       active. Nothing built here is executed.
set -eu
cd "$(dirname "$0")/.."
RECAULK_TEST_PHASE=build
. tests/helpers/built.sh
[ "$(uname -s)" = Darwin ] || { echo "SKIP: the strict analyzer runs on macOS only"; exit 77; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
d="$(mktemp -d "${TMPDIR:-/tmp}/objc-provider-groups.XXXXXX")"
d="$(cd "$d" && pwd -P)"
[ -n "${RECAULK_KEEP:-}" ] || trap 'rm -rf "$d"' EXIT
mkdir "$d/root" "$d/src"
# spec: README.md "Objective-C methods" -- Recaulk's own Drydock pin, fetched as shipyard fetches its pin (as
#       tests/strict-guard-consumer.sh does), with that Drydock's reference set: a release credits its groups with the
#       Drydock it adopted; consumers verify with shipyard's pin, which catches up
mkdir "$d/pin"
printf 'v%s\n' "$(tr -d ' \t\n' < components/drydock/version)" > "$d/pin/version"
DRYDOCK="$(sh "$SHIPYARD_SCRIPTS/fetch_drydock.sh" "$d/pin" | tail -1)"
REF="$DRYDOCK/share/drydock/objc/reference"
X="$DRYDOCK/bin/drydock-objc"
GIDS="recaulk.nstimer.block-timers.v1 recaulk.nscolor.label-colors.v1 recaulk.nsgraphicscontext.cgcontext.v1
recaulk.nsview.accessibility.v1 recaulk.nscell.accessibility.v1"
set --
for g in $GIDS; do set -- "$@" --provider "$g"; done
"$X" link-args --prefix "$T" --link-map "$d/root/consumer.map" "$@" > "$d/args" 2> "$d/err" \
  || { echo "FAIL: link-args refused the groups: $(cat "$d/err")"; exit 1; }
set --
while IFS= read -r l; do set -- "$@" "$l"; done < "$d/args"
cp tests/c/objc_group_consumer.m "$d/src/"
"$CC" $FLAGS -fno-objc-arc -fblocks -O1 "$d/src/objc_group_consumer.m" "$@" -o "$d/root/consumer"
"$X" evidence --artifact "$d/root/consumer" --prestrip "$d/root/consumer" --source-root "$d/src" \
  --link-map "$d/root/consumer.map" --provider-prefix "$T" --references "$REF" --output "$d/evidence.json" 2> "$d/err" \
  || { echo "FAIL: drydock-objc evidence: $(cat "$d/err")"; exit 1; }
rc=0
# spec: tests/objc-source-receipt.sh -- as a consumer's guard does (shipyard assert_binary_compatible.sh), the analysis
#       closes the provider bodies' own sends from the stage's source receipt
"$X" analyze --artifact "$d/root/consumer" --root "$d/root" --references "$REF" --report "$d/report" --mode strict \
  --build-evidence "$d/evidence.json" --provider-prefix "$T" --source-receipt "$T/share/recaulk/objc-source.receipt" \
  2> "$d/err" || rc=$?
for sel in scheduledTimerWithTimeInterval:repeats:block: timerWithTimeInterval:repeats:block: labelColor linkColor \
  graphicsContextWithCGContext:flipped: setAccessibilityLabel: accessibilityLabel setAccessibilityRole: \
  accessibilityRole setAccessibilityChildren: accessibilityChildren setAccessibilitySelectedTextRange: \
  accessibilitySelectedTextRange accessibilityFrame; do
  v=$(grep "\"selector\": \"$sel\"" "$d/report" | sed -n 's/.*"verdict": "\([^"]*\)".*/\1/p' | sort -u | tr '\n' ' ')
  [ "$v" = "provided " ] || bad "$sel is '${v:-no finding}', not provided (analyze exit $rc)"
done
for g in $GIDS; do
  grep "\"$g\"" "$d/report" | grep -q '"status": "active"' || bad "group $g is not reported active"
done
# spec: README.md "Objective-C methods" -- the only open sends left are the providers' own bodies', which strict
#       never exempts, so strict passes exactly when none is left
if grep -Eq '"verdict": "(unsupported|unresolved)"' "$d/report"; then [ "$rc" = 1 ] || bad "analyze exit $rc with open sends, not 1"
else [ "$rc" = 0 ] || bad "analyze exit $rc with every send closed"; fi
if grep -q '"code": ' "$d/report"; then bad "the analysis reports errors:"; grep '"code": ' "$d/report" | head -10; fi
[ "$fail" = 0 ] || { tail -5 "$d/err"; exit 1; }
echo "objc-provider-groups OK"
