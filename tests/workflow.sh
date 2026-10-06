#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
w=.github/workflows/release.yml
grep -Eq 'uses: Mavergreen/shipyard/\.github/actions/install@v1' "$w" \
  || { echo "install action not pinned to @v1"; exit 1; }
grep -q 'cmake --install' "$w" && { echo "must NOT hand-install shipyard in CI"; exit 1; }
grep -q 'submodule' "$w" && { echo "must NOT submodule shipyard"; exit 1; }
grep -q 'build/version.sh' "$w" && { echo "the version is derived in the workflow, not by build/version.sh"; exit 1; }
grep -Eq '^[[:space:]]*tags:' "$w" && { echo "a tag must not trigger a release"; exit 1; }
grep -q 'build/build-lib.sh' "$w" || { echo "workflow must build the library"; exit 1; }
grep -q 'build/package-pkg.sh' "$w" || { echo "workflow must package"; exit 1; }
grep -q 'SPARKLE_PRIVATE_KEY' "$w" || { echo "workflow must sign"; exit 1; }
grep -q 'publish-release.yml@v1' "$w" || { echo "workflow must publish via the shared publish-release.yml"; exit 1; }
grep -q 'gh release create' "$w" && { echo "must NOT hand-roll publishing; use publish-release.yml"; exit 1; }
grep -q 'RELEASE_NOTES.md' "$w" || { echo "the notes must travel in the artifact as RELEASE_NOTES.md"; exit 1; }
grep -q 'fetch-depth: 0' "$w" || { echo "checkout must fetch tags (fetch-depth: 0)"; exit 1; }

lineof() { grep -n "$1" "$w" | head -1 | cut -d: -f1; }
b="$(lineof 'sh build/build-lib.sh')"; t="$(lineof 'sh "\$SHIPYARD_SCRIPTS/run-repo-tests.sh"')"
[ -n "$b" ] && [ -n "$t" ] && [ "$b" -lt "$t" ] || { echo "build-lib.sh must run before run-repo-tests.sh"; exit 1; }
for s in release-state-record.sh check-ingredient-pins.sh stand-in-feeds.sh; do
  grep -q "$s" "$w" || { echo "workflow must call $s"; exit 1; }
done
grep -q -- '--product recaulk' "$w" || { echo "signing must use --product recaulk"; exit 1; }
grep -q -- '--product Recaulk' "$w" || { echo "notes must use --product Recaulk"; exit 1; }
grep -q 'name: Exactly one .pkg, named recaulk-<version>.pkg' "$w" || { echo "the one-pkg step is missing"; exit 1; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/workflow.XXXXXX")"   # template: 10.9 BSD mktemp requires one
trap 'rm -rf "$tmp"' EXIT
awk '
  /^ *id: ver$/ { seen = 1; next }
  seen && !on && /^ *run: \|$/ { on = 1; next }
  on { if ($0 !~ /^ *$/ && $0 !~ /^          /) exit; sub(/^          /, ""); print }
' "$w" > "$tmp/ver.sh"
[ -s "$tmp/ver.sh" ] || { echo "could not extract the ver step's script"; exit 1; }
mkdir "$tmp/stubs" "$tmp/repo"
printf '#!/bin/sh\necho stub-digest\n' > "$tmp/stubs/release-state.sh"
printf '#!/bin/sh\necho PUBLISH\n' > "$tmp/stubs/release-needed.sh"
printf '20261005\n' > "$tmp/repo/UPSTREAM_VERSION"
ver_publish() {   # ref event repackage
  rm -f "$tmp/out"
  ( cd "$tmp/repo" && GITHUB_REF="$1" GITHUB_EVENT_NAME="$2" REPACKAGE="$3" SHIPYARD_SCRIPTS="$tmp/stubs" \
      GITHUB_OUTPUT="$tmp/out" sh -c "git init -q . 2>/dev/null; sh \"$tmp/ver.sh\"" >/dev/null ) \
    || { echo "the ver step's script failed for $1 $2"; exit 1; }
  sed -n 's/^publish=//p' "$tmp/out"
}
expect() {   # want ref event repackage
  got="$(ver_publish "$2" "$3" "$4")"
  [ "$got" = "$1" ] || { echo "publish for $2 $3 repackage=$4: want $1, got $got"; exit 1; }
}
expect yes refs/heads/main workflow_dispatch false
expect yes refs/heads/main workflow_dispatch true
expect no refs/heads/main push false
expect no refs/pull/1/merge pull_request false
expect no refs/heads/renovate/x workflow_dispatch true
expect no refs/heads/renovate/x workflow_dispatch false
expect no refs/heads/feature workflow_dispatch true
[ "$(grep -c "github.ref == 'refs/heads/main'" "$w")" -eq 2 ] || { echo "scan and publish jobs must each require github.ref == 'refs/heads/main'"; exit 1; }
if grep -q 'dist/' "$w"; then
  grep -Eq '^dist/' .mavericks-intree || { echo "release.yml writes dist/, so .mavericks-intree must list it"; exit 1; }
fi
rc=.github/workflows/reconcile.yml
grep -q 'actions: write' "$rc" || { echo "reconcile.yml needs actions: write"; exit 1; }
rp=.github/workflows/repackage-on-ingredient-bump.yml
for s in components/macports-legacy-support/version components/drydock/version repackage=true; do
  grep -q "$s" "$rp" || { echo "repackage-on-ingredient-bump.yml must name $s"; exit 1; }
done
pb=.github/workflows/pins-bot.yml
on_block="$(sed -n '/^on:/,/^permissions:/p' "$pb" | sed '1d;$d' | grep -v '^[[:space:]]*$')"
[ "$(printf '%s\n' "$on_block" | grep -Ec '^  [a-z_]+:')" -eq 1 ] && printf '%s\n' "$on_block" | grep -Eq '^  push:$' \
  || { echo "pins-bot.yml must trigger on push only"; exit 1; }
[ "$(printf '%s\n' "$on_block" | wc -l | tr -d ' ')" -eq 2 ] && printf '%s\n' "$on_block" | grep -Eq "^    branches: \['renovate/\*\*'\]$" \
  || { echo "pins-bot.yml must trigger on renovate/** only"; exit 1; }
grep -q '^permissions: {}$' "$pb" || { echo "pins-bot.yml must have permissions: {} at the top"; exit 1; }
echo "workflow OK"
