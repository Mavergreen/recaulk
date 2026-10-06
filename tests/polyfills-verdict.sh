#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/macos.sh
. tests/helpers/polyfills.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/polyfills-verdict-test.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

dev=tests/fixtures/known-macports-deviations.txt
fb=tests/fixtures/fallback-only-checks.txt
canned=tests/fixtures/test-polyfills-10.9.5.out
mkdir "$D/bin"
printf '#!/bin/sh\n[ "$1" = -productVersion ] || exit 2\nprintf "%%s\\n" "$FAKE_VERSION"\n' > "$D/bin/sw_vers"
chmod +x "$D/bin/sw_vers"

entropy='getentropy(big, 257) == -1 && errno == EIO'
clone='clonefile("/etc/hosts", "/tmp/mls_clone_xyz", 0) == -1 && errno == ENOTSUP'
swap() {
  awk -v a="$2" -v b="$3" '$0 == a { print b; seen = 1; next } { print } END { exit !seen }' "$1"
}
swap "$canned" "  FAIL : $entropy  (errno=0 Undefined error: 0)" "  ok   : $entropy" > "$D/sys1" \
  || { echo "FAIL: $canned has no FAIL line for $entropy"; exit 1; }
swap "$D/sys1" "  ok   : $clone" "  FAIL : $clone  (errno=0 Undefined error: 0)" > "$D/system.out" \
  || { echo "FAIL: $canned has no ok line for $clone"; exit 1; }
sed '$s/.*/PASS/' "$D/sys1" > "$D/system-clone-ok.out"
cp "$canned" "$D/extra.out"
printf '  FAIL : notify_is_valid_token(0) == false  (errno=0 Undefined error: 0)\n' >> "$D/extra.out"
grep -Fv -- "$entropy" "$canned" > "$D/stale.out"
grep -v '^  FAIL : ' "$canned" > "$D/nofail.out"
swap "$canned" "  FAIL : $entropy  (errno=0 Undefined error: 0)" "  FAIL : $entropy  (errno=22 Invalid argument)" > "$D/sys26" \
  || { echo "FAIL: $canned has no FAIL line for $entropy"; exit 1; }
swap "$D/sys26" "  ok   : $clone" "  FAIL : $clone  (errno=22 Invalid argument)" | sed '$s/.*/FAILED (2 checks)/' > "$D/macos26.out"

judge() {
  got="$(PATH="$D/bin:$PATH" FAKE_VERSION="$1"; export PATH FAKE_VERSION
    polyfills_verdict "$3" "$2" "${4:-$dev}" "${5:-$fb}" 2>&1)" && vrc=0 || vrc=$?
}
passes() {
  judge "$@"
  [ "$vrc" = 0 ] || { bad "on $1, $3 (exit $2) should be accepted: $got"; return 1; }
}
fails_with() {
  want="$1"; shift
  judge "$@"
  [ "$vrc" != 0 ] || { bad "on $1, $3 (exit $2) should be rejected: $got"; return 0; }
  case "$got" in *"$want"*) ;; *) bad "on $1, $3 (exit $2) was rejected without '$want': $got" ;; esac
}

passes 10.9.5 1 "$canned" \
  && case "$got" in *"tolerated known deviation on 10.9.5, where MacPorts' implementation runs: $entropy"*) ;;
       *) bad "10.9.5 does not report the tolerated getentropy deviation: $got" ;; esac
passes 10.11.6 1 "$canned" || true
passes 14.0 1 "$D/system.out" \
  && case "$got" in *"not judged on 14.0, where the system's implementation runs: $clone"*) ;;
       *) bad "14.0 does not report the clonefile assertion as not judged: $got" ;; esac
passes 10.12 1 "$D/system.out" || true
passes 26.0 0 "$D/system-clone-ok.out" || true

passes 26.6.2 1 "$D/macos26.out" \
  && case "$got" in *"not judged on 26.6.2, where the system's implementation runs: $entropy"*) ;;
       *) bad "26.6.2 does not report the getentropy assertion as not judged: $got" ;; esac
passes 14.0 1 "$canned" || true
fails_with "test_polyfills on 26.6.2: unexpected failure: notify_is_valid_token(0) == false" 26.6.2 1 "$D/extra.out"
fails_with "MacPorts fixed it on 10.9.5" 10.9.5 1 "$D/system.out"
fails_with "test_polyfills on 10.9.5: unexpected failure: $clone" 10.9.5 1 "$D/system.out"
fails_with "unexpected failure: notify_is_valid_token(0) == false" 10.9.5 1 "$D/extra.out"
fails_with "stale entry" 10.9.5 1 "$D/stale.out"
fails_with "stale entry" 14.0 1 "$D/stale.out"
fails_with "died with status 139" 10.9.5 139 "$canned"
fails_with "exited 1 with no FAIL line" 10.9.5 1 "$D/nofail.out"
printf '%s\n' "$entropy" > "$D/no-era.txt"
fails_with "want '<MAJOR.MINOR<TAB>condition'" 10.9.5 1 "$canned" "$D/no-era.txt"
printf '#!/bin/sh\nexit 1\n' > "$D/bin/sw_vers"
fails_with "cannot judge test_polyfills" 10.9.5 1 "$canned"

[ "$fail" = 0 ] && echo "polyfills-verdict OK"
exit $fail
