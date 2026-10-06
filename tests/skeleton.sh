#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
fail=0
grep -Eq '^[0-9]{8}$' UPSTREAM_VERSION || { echo "FAIL: UPSTREAM_VERSION not a bare YYYYMMDD"; fail=1; }
pin=components/macports-legacy-support/version
if [ -f "$pin" ] && [ "$(wc -l < "$pin" | tr -d ' ')" = 4 ]; then
  n=0
  for pat in '^REPO=https://github\.com/macports/macports-legacy-support\.git$' '^REF=v[0-9]+\.[0-9]+\.[0-9]+$' \
             '^DIGEST=[0-9a-f]{40}$' '^TARBALL_SHA256=[0-9a-f]{64}$'; do
    n=$((n + 1))
    sed -n "${n}p" "$pin" | grep -Eq "$pat" || { echo "FAIL: $pin line $n does not match $pat"; fail=1; }
  done
else
  echo "FAIL: $pin must exist and be exactly four lines"; fail=1
fi
for pat in '^/VERSION$' '^/dist/$' '^/\.superpowers/$' '^/\.idea/$'; do
  grep -Eq "$pat" .gitignore || { echo "FAIL: .gitignore missing $pat"; fail=1; }
done
if grep -Eq '^/?build/?$' .gitignore; then
  echo "FAIL: build/*.sh are tracked; ignoring build/ hides new ones from git add (conventions check 7c)"; fail=1
fi
icns=updater/recaulk-updater.icns
[ -f "$icns" ] && file "$icns" | grep -qi 'icon' || { echo "FAIL: $icns is missing or not an icon"; fail=1; }
for f in LICENSE comment-reasons; do
  [ -f "$f" ] || { echo "FAIL: $f missing"; fail=1; }
done
[ "$fail" = 0 ] && echo "skeleton OK"
exit $fail
