#!/bin/sh
# platform: macOS-only -- pkgbuild and productbuild make the fixture product archive
set -eu
# platform: ls and sort order names by the locale's collation, which ignores case in macOS 26's en_US.UTF-8 and compares bytes in 10.9's
LC_ALL=C
export LC_ALL
cd "$(dirname "$0")/.."
D="$(mktemp -d "${TMPDIR:-/tmp}/fetch-drydock.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

want=usr/local/mavergreen/drydock/bin/drydock-macho-rewrite
mkdir -p "$D/base/$(dirname "$want")" "$D/dd/$(dirname "$want")"
printf 'decoy bytes\n' > "$D/base/$want"
printf 'stub bytes\n' > "$D/dd/$want"
pkgbuild --quiet --root "$D/base" --identifier dev.mavergreen.base --version 1 --install-location / "$D/mavergreen-base.pkg"
pkgbuild --quiet --root "$D/dd" --identifier dev.mavergreen.drydock --version 0.0.1 --install-location / "$D/drydock-component.pkg"
rel="$D/rel/v0.0.1"
mkdir -p "$rel"
productbuild --quiet --package "$D/mavergreen-base.pkg" --package "$D/drydock-component.pkg" "$D/full.pkg"
productbuild --quiet --package "$D/mavergreen-base.pkg" "$D/baseonly.pkg"
cp "$D/full.pkg" "$rel/drydock-0.0.1.pkg"
good="$(shasum -a 256 "$rel/drydock-0.0.1.pkg" | cut -d' ' -f1)"
DRYDOCK_RELEASES="file://$D/rel"
export DRYDOCK_RELEASES

run() {
  mkdir "$D/$1"
  rc=0
  out="$(sh build/fetch-drydock.sh 0.0.1 "$D/$1" 2>"$D/$1.err")" || rc=$?
  err="$(cat "$D/$1.err")"
}

printf '%s  drydock-0.0.1.pkg\n' "$good" > "$rel/SHA256SUMS"
run ok
[ "$rc" = 0 ] || bad "a listed, matching pkg was refused (rc $rc): $err"
[ "$out" = "$D/ok/drydock-macho-rewrite" ] || bad "printed '$out', want $D/ok/drydock-macho-rewrite"
[ -x "$D/ok/drydock-macho-rewrite" ] || bad "OUTDIR/drydock-macho-rewrite is missing or not executable"
[ "$(cat "$D/ok/drydock-macho-rewrite" 2>/dev/null)" = "stub bytes" ] \
  || bad "extracted '$(cat "$D/ok/drydock-macho-rewrite" 2>/dev/null)', want the dev.mavergreen.drydock component's stub, not the first component's decoy"
[ "$(ls -A "$D/ok" | tr '\n' ' ')" = ".cache drydock-macho-rewrite " ] || bad "OUTDIR holds more than the tool and its cache: $(ls -A "$D/ok" | tr '\n' ' ')"
[ "$(ls "$D/ok/.cache/v0.0.1" 2>/dev/null | tr '\n' ' ')" = "SHA256SUMS drydock-0.0.1.pkg " ] \
  || bad "the verified pkg and its SHA256SUMS are not cached under OUTDIR/.cache/v0.0.1"

rerun() {
  rc=0
  out="$(DRYDOCK_RELEASES="$2" sh build/fetch-drydock.sh 0.0.1 "$D/$1" 2>"$D/$1.err")" || rc=$?
  err="$(cat "$D/$1.err")"
}
rm -f "$D/ok/drydock-macho-rewrite"
rerun ok "file://$D/nowhere"
[ "$rc" = 0 ] || bad "a second run with the releases unreachable did not use the cache (rc $rc): $err"
[ "$(cat "$D/ok/drydock-macho-rewrite" 2>/dev/null)" = "stub bytes" ] || bad "a run from the cache did not extract the stub"

printf 'x' >> "$D/ok/.cache/v0.0.1/drydock-0.0.1.pkg"
rerun ok "file://$D/nowhere"
[ "$rc" = 1 ] || bad "a tampered cached pkg with the releases unreachable exited $rc, want 1 (fail closed)"
[ ! -e "$D/ok/.cache/v0.0.1/drydock-0.0.1.pkg" ] || bad "a tampered cached pkg was kept"
printf 'x' > "$D/tampered"
mkdir -p "$D/ok/.cache/v0.0.1"
cp "$rel/SHA256SUMS" "$D/ok/.cache/v0.0.1/SHA256SUMS"
cat "$rel/drydock-0.0.1.pkg" "$D/tampered" > "$D/ok/.cache/v0.0.1/drydock-0.0.1.pkg"
rerun ok "file://$D/rel"
[ "$rc" = 0 ] || bad "a tampered cached pkg was not fetched again (rc $rc): $err"
case "$err" in *"does not match its cached SHA256SUMS"*) ;; *) bad "a tampered cached pkg was reused silently: $err" ;; esac
cmp -s "$D/ok/.cache/v0.0.1/drydock-0.0.1.pkg" "$rel/drydock-0.0.1.pkg" || bad "the refetched pkg did not replace the tampered one in the cache"

printf '%s *drydock-0.0.1.pkg\n' "$good" > "$rel/SHA256SUMS"
run star
[ "$rc" = 0 ] || bad "a *-marked sum line was refused (rc $rc): $err"

printf '%064d  drydock-0.0.1.pkg\n' 0 > "$rel/SHA256SUMS"
run wrong
[ "$rc" = 1 ] || bad "a wrong sum exited $rc, want 1"
case "$err" in *"does not match"*) ;; *) bad "a wrong sum does not say 'does not match': $err" ;; esac
[ -z "$(ls -A "$D/wrong")" ] || bad "a wrong sum left $(ls -A "$D/wrong" | tr '\n' ' ') in OUTDIR"

printf '%s  drydock-0.0.1.pkg.asc\n' "$good" > "$rel/SHA256SUMS"
run nearmiss
[ "$rc" = 1 ] || bad "a near-miss name exited $rc, want 1"
case "$err" in *"not listed"*) ;; *) bad "a near-miss name does not say 'not listed': $err" ;; esac
[ -z "$(ls -A "$D/nearmiss")" ] || bad "a near-miss name left $(ls -A "$D/nearmiss" | tr '\n' ' ') in OUTDIR"

printf '%s  other-asset\n' "$good" > "$rel/SHA256SUMS"
run unlisted
[ "$rc" = 1 ] || bad "an unlisted pkg exited $rc, want 1"
case "$err" in *"not listed"*) ;; *) bad "an unlisted pkg does not say 'not listed': $err" ;; esac
[ -z "$(ls -A "$D/unlisted")" ] || bad "an unlisted pkg left $(ls -A "$D/unlisted" | tr '\n' ' ') in OUTDIR"

cp "$D/baseonly.pkg" "$rel/drydock-0.0.1.pkg"
printf '%s  drydock-0.0.1.pkg\n' "$(shasum -a 256 "$rel/drydock-0.0.1.pkg" | cut -d' ' -f1)" > "$rel/SHA256SUMS"
run nocomponent
[ "$rc" = 1 ] || bad "a pkg without a dev.mavergreen.drydock component exited $rc, want 1"
case "$err" in *dev.mavergreen.drydock*) ;; *) bad "a pkg without the component does not name dev.mavergreen.drydock: $err" ;; esac
[ -z "$(ls -A "$D/nocomponent")" ] || bad "a pkg without the component left $(ls -A "$D/nocomponent" | tr '\n' ' ') in OUTDIR"

[ "$fail" = 0 ] && echo "fetch-drydock OK"
exit $fail
