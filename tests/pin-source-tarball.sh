#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail() { echo "FAIL: $*" >&2; exit 1; }
# platform: OS X 10.9's /usr/bin/git is a Command Line Tools stub, there whether or not they are installed.
git --version >/dev/null 2>&1 || { echo "no git that runs -- skipping"; exit 77; }
[ -f build/pin-source-tarball.sh ] || fail "build/pin-source-tarball.sh does not exist"
unset MAVERICKS_ROOT
. build/msc.sh
T="$(mktemp -d "${TMPDIR:-/tmp}/pin-source-tarball.XXXXXX")"
trap 'rm -rf "$T"' EXIT
T="$(CDPATH='' cd -P -- "$T" && pwd -P)"
R="$T/repo"; V="$R/components/macports-legacy-support/version"
mkdir -p "$R/build" "$R/components/macports-legacy-support" "$T/shipyard" "$T/tarballs" "$T/tmp"
cp "$ROOT/build/pin-source-tarball.sh" "$ROOT/build/lib.sh" "$ROOT/build/msc.sh" "$R/build/"
cp "$SHIPYARD/lib.sh" "$T/shipyard/lib.sh"
g="$T/up/macports-legacy-support"; mkdir -p "$g/sub"
git -C "$g" init -q; git -C "$g" config user.email t@t; git -C "$g" config user.name t
echo fixture > "$g/sub/file.txt"; printf '#!/bin/sh\n' > "$g/run.sh"; chmod +x "$g/run.sh"; ln -s sub/file.txt "$g/link"
git -C "$g" add -A; git -C "$g" commit -qm fixture
C="$(git -C "$g" rev-parse HEAD)"
git -C "$g" archive --format=tar --prefix="macports-legacy-support-$C/" HEAD | gzip -n > "$T/tarballs/macports-legacy-support-$C.tar.gz"
Z=0000000000000000000000000000000000000000000000000000000000000000
printf 'REPO=https://github.com/macports/macports-legacy-support.git\nREF=v1.5.2\nDIGEST=%s\nTARBALL_SHA256=%s\n' "$C" "$Z" > "$V"
cat > "$T/shipyard/fetch_pinned_source.sh" <<F
#!/bin/sh
[ "\$1" = --url ] || exit 9
case "\$3" in *[!0-9a-f]*|'') echo "fetch_pinned_source: '\$3' is not a commit (40 hex digits)" >&2; exit 2 ;; esac
n="\${2##*/}"; n="\${n%.git}"
echo "file://$T/tarballs/\$n-\$3.tar.gz"
F
cat > "$T/shipyard/clone_pinned.sh" <<F
#!/bin/sh
n="\${1##*/}"; n="\${n%.git}"
git clone -q "$T/up/\$n" "\$4" && [ "\$(git -C "\$4" rev-parse HEAD)" = "\$3" ]
F
pins() { TMPDIR="$T/tmp" SHIPYARD_SCRIPTS="$T/shipyard" sh "$R/build/pin-source-tarball.sh" "$@"; }
run() { rc=0; pins "$@" > "$T/out" 2>&1 || rc=$?; }
want() { [ "$rc" = "$1" ] || fail "$2: exit $rc, not $1: $(cat "$T/out")"; }
tarball() {
  rm -rf "$T/fake"; mkdir -p "$T/fake"
  git -C "$g" archive --format=tar --prefix="macports-legacy-support-$C/" HEAD | tar xf - -C "$T/fake"
  ( cd "$T/fake/macports-legacy-support-$C" && eval "$1" )
  ( cd "$T/fake" && tar cf - "macports-legacy-support-$C" | gzip -n > "$T/tarballs/macports-legacy-support-$C.tar.gz" )
}
sum() { shasum -a 256 < "$T/tarballs/macports-legacy-support-$C.tar.gz" | cut -c1-64; }
left() { ls -A "$T/tmp"; ls -A "$R/components/macports-legacy-support" | grep -vx version || true; }
cp "$V" "$T/stale"

echo "-- usage: exit 2, nothing written"
for a in --bogus "--check --check" "--check extra" -- -; do
  # shellcheck disable=SC2086
  run $a; want 2 "usage [$a]"
  grep -q "^usage: " "$T/out" || fail "usage [$a] printed: $(cat "$T/out")"
done
cmp -s "$T/stale" "$V" || fail "a usage error wrote the pin file"

echo "-- --check: exit 3 on a stale pin, writing nothing; exit 0 on a current one"
run --check; want 3 "--check on a stale pin"
cmp -s "$T/stale" "$V" || fail "--check wrote the pin file"
[ -z "$(left)" ] || fail "--check left $(left)"

echo "-- writes the tarball's SHA-256 and nothing else; again, unchanged"
run; want 0 "a first run"
grep -qx "TARBALL_SHA256=$(sum)" "$V" || fail "TARBALL_SHA256: $(cat "$V")"
[ "$(diff "$T/stale" "$V" | grep -c '^[<>]')" = 2 ] || fail "changed more than one line: $(diff "$T/stale" "$V")"
[ -z "$(left)" ] || fail "a write left $(left)"
cp "$V" "$T/current"
run --check; want 0 "--check on a current pin"
run; want 0 "a second run"
cmp -s "$T/current" "$V" || fail "a second run changed the pin file"

echo "-- a tarball that is not its commit's tree is refused: exit 1, nothing written, nothing left"
cp "$T/stale" "$V"
missed=""
while IFS= read -r m; do
  tarball "$m"
  for mode in "" --check; do
    # shellcheck disable=SC2086
    run $mode
    if [ "$rc" != 1 ] || ! grep -q "is not commit $C's tree" "$T/out"; then missed="$missed
  [$m] ${mode:-write}: exit $rc: $(tail -1 "$T/out")"; fi
    cmp -s "$T/stale" "$V" || { missed="$missed
  [$m] ${mode:-write}: wrote the pin file"; cp "$T/stale" "$V"; }
    [ -z "$(left)" ] || fail "[$m] $mode: left $(left)"
  done
done <<'M'
echo "not the commit" > sub/file.txt
mkdir -p .git/hooks && echo x > .git/hooks/x
mkdir sub/.git && echo x > sub/.git/config
echo "gitdir: /elsewhere" > sub/.git
mkdir empty
mv run.sh RUN.sh
M
[ -z "$missed" ] || fail "tarballs not their commit's tree, not refused:$missed"
tarball true

echo "-- every other failure is exit 1, never a command's own 2: nothing written, nothing left"
sed "s/^DIGEST=.*/DIGEST=nope/" "$T/stale" > "$T/bad"; cp "$T/bad" "$V"
run; want 1 "a malformed DIGEST"
grep -q "'nope' is not a commit" "$T/out" || fail "a malformed DIGEST: $(cat "$T/out")"
cmp -s "$T/bad" "$V" || fail "a malformed DIGEST: wrote the pin file"
grep -v '^TARBALL_SHA256=' "$T/stale" > "$T/bad"; cp "$T/bad" "$V"
for mode in "" --check; do
  # shellcheck disable=SC2086
  run $mode; want 1 "no TARBALL_SHA256 line ${mode:-write}"
  cmp -s "$T/bad" "$V" || fail "no TARBALL_SHA256 line: wrote the pin file"
done
cp "$T/stale" "$V"
mv "$T/tarballs/macports-legacy-support-$C.tar.gz" "$T/gone.tar.gz"
run; want 1 "an unfetchable tarball"
cmp -s "$T/stale" "$V" || fail "an unfetchable tarball: wrote the pin file"
[ -z "$(left)" ] || fail "an unfetchable tarball left $(left)"
mv "$T/gone.tar.gz" "$T/tarballs/macports-legacy-support-$C.tar.gz"

echo "-- a TERM ends it at once: exit 143, nothing written, no temp file left"
{ printf '#!/bin/sh\nkill -TERM $PPID; sleep 1; exit 1\n'; } > "$T/shipyard/clone_pinned.sh"
run; want 143 "a TERM"
cmp -s "$T/stale" "$V" || fail "a TERM: wrote the pin file"
[ -z "$(left)" ] || fail "a TERM left $(left)"
echo "pin-source-tarball OK"
