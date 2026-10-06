#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
command -v python3 >/dev/null 2>&1 || { echo "no python3 -- skipping" >&2; exit 77; }
f=.github/renovate.json
python3 -m json.tool "$f" >/dev/null || { echo "invalid JSON"; exit 1; }
python3 - "$f" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
assert "github>Mavergreen/shipyard" in c.get("extends", []), "must extend the shared preset"
cm = c.get("customManagers", [])
for x in cm:
    assert not any("UPSTREAM_VERSION" in p for p in x.get("managerFilePatterns", [])), "no manager may match UPSTREAM_VERSION"
m = [x for x in cm if x.get("managerFilePatterns") == ["/^components/macports-legacy-support/version$/"]]
assert m, "no customManager for the MacPorts pin file"
m = m[0]
assert m["matchStrings"] == ["REPO=(?<packageName>\\S+?)\\.git\\s+REF=(?<currentValue>\\S+)\\s+DIGEST=(?<currentDigest>[0-9a-f]{40})"], "wrong matchStrings"
assert m["datasourceTemplate"] == "git-refs", "wrong datasource"
assert m["versioningTemplate"] == "semver", "wrong versioning"
assert c.get("gitIgnoredAuthors") == ["41898282+github-actions[bot]@users.noreply.github.com"], "gitIgnoredAuthors"
r = [x for x in c.get("packageRules", []) if "macports/macports-legacy-support" in x.get("matchDepNames", [])]
assert r, "no packageRule for macports/macports-legacy-support"
notes = " ".join(r[0].get("prBodyNotes", []))
assert "pins-bot.yml" in notes and "sh build/pin-source-tarball.sh" in notes, "prBodyNotes must name pins-bot.yml and sh build/pin-source-tarball.sh"
assert "automerge" not in r[0], "the rule must not override automerge"
print("renovate OK")
PY
