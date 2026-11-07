#!/bin/sh
# platform: host-agnostic
set -eu
LC_ALL=C
export LC_ALL
cd "$(dirname "$0")/.."
D="$(mktemp -d "${TMPDIR:-/tmp}/fetch-drydock-linux.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

v=0.3.0
mkdir -p "$D/src/drydock-$v/bin" "$D/rel/v$v"
printf 'linux tool\n' > "$D/src/drydock-$v/bin/drydock-macho-rewrite"
printf 'other\n' > "$D/src/drydock-$v/bin/change_dylib"
tar -czf "$D/rel/v$v/drydock-$v-linux-x86_64.tar.gz" -C "$D/src" "drydock-$v"
good="$(sha256 "$D/rel/v$v/drydock-$v-linux-x86_64.tar.gz")"
DRYDOCK_RELEASES="file://$D/rel"; DRYDOCK_HOST=linux
export DRYDOCK_RELEASES DRYDOCK_HOST

run() {
  mkdir "$D/$1"
  rc=0
  out="$(sh build/fetch-drydock.sh "$2" "$D/$1" 2>"$D/$1.err")" || rc=$?
  err="$(cat "$D/$1.err")"
}

printf '%s  drydock-%s-linux-x86_64.tar.gz\n' "$good" "$v" > "$D/rel/v$v/SHA256SUMS"
run ok "$v"
[ "$rc" = 0 ] || bad "a listed, matching Linux archive was refused (rc $rc): $err"
[ "$out" = "$D/ok/drydock-macho-rewrite" ] || bad "printed '$out', want $D/ok/drydock-macho-rewrite"
[ -x "$D/ok/drydock-macho-rewrite" ] || bad "OUTDIR/drydock-macho-rewrite is missing or not executable"
[ "$(cat "$D/ok/drydock-macho-rewrite" 2>/dev/null)" = "linux tool" ] || bad "did not extract the archive's bin/drydock-macho-rewrite"
[ "$(ls "$D/ok/.cache/v$v" 2>/dev/null | tr '\n' ' ')" = "SHA256SUMS drydock-$v-linux-x86_64.tar.gz " ] \
  || bad "the verified archive and its SHA256SUMS are not cached under OUTDIR/.cache/v$v"

rm -f "$D/ok/drydock-macho-rewrite"
rc=0; out="$(DRYDOCK_RELEASES="file://$D/nowhere" sh build/fetch-drydock.sh "$v" "$D/ok" 2>"$D/ok.err")" || rc=$?
[ "$rc" = 0 ] && [ "$(cat "$D/ok/drydock-macho-rewrite" 2>/dev/null)" = "linux tool" ] \
  || bad "a second run with the releases unreachable did not use the cache (rc $rc): $(cat "$D/ok.err")"

printf '%064d  drydock-%s-linux-x86_64.tar.gz\n' 0 "$v" > "$D/rel/v$v/SHA256SUMS"
run wrong "$v"
[ "$rc" = 1 ] || bad "a wrong sum exited $rc, want 1"
case "$err" in *"does not match"*) ;; *) bad "a wrong sum does not say 'does not match': $err" ;; esac
[ -z "$(ls -A "$D/wrong")" ] || bad "a wrong sum left $(ls -A "$D/wrong" | tr '\n' ' ') in OUTDIR"

printf '%s  drydock-%s.pkg\n' "$good" "$v" > "$D/rel/v$v/SHA256SUMS"
run unlisted "$v"
[ "$rc" = 1 ] || bad "an unlisted Linux archive exited $rc, want 1"
case "$err" in *"not listed"*) ;; *) bad "an unlisted Linux archive does not say 'not listed': $err" ;; esac

run old 0.2.2
[ "$rc" = 1 ] || bad "drydock 0.2.2 on a Linux host exited $rc, want 1"
case "$err" in *"0.3.0"*) ;; *) bad "the refusal of drydock 0.2.2 on Linux does not name 0.3.0, the first release with a Linux archive: $err" ;; esac
[ -z "$(ls -A "$D/old")" ] || bad "a refused version left $(ls -A "$D/old" | tr '\n' ' ') in OUTDIR"

[ "$fail" = 0 ] && echo "fetch-drydock-linux OK"
exit $fail
