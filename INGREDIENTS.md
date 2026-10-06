# Build ingredients

Everything baked into what Recaulk ships, and how a change to it reaches a release.

Recaulk is **its own upstream**: it is versioned `YYYYMMDD.N` and nothing external releases it.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Recaulk's own source (own upstream) | `UPSTREAM_VERSION`: the date of the newest source a release carries, bumped by hand | ❌ untrackable: nothing external releases it | bumping it on `main` is the decision to release |
| MacPorts macports-legacy-support | `components/macports-legacy-support/version` | ✅ `git-refs` (REF+DIGEST; the pins bot writes TARBALL_SHA256) | publishes a `.N+1` repackage |
| MacOSX10.9 SDK, CMake modules, packaging and signing scripts | `Mavergreen/shipyard@v1` | ✅ github-actions manager tracks the tag | `@v1` moves without the pin changing, so nothing repackages by itself |
| `drydock-macho-rewrite`, the forwarding layer's symbol renamer | `components/drydock/version`, extracted from `drydock-<ver>.pkg` verified against its release's `SHA256SUMS` at build time | ✅ github-releases manager tracks `Mavergreen/drydock` | a bump repackages via the ingredient-bump workflow (drydock depends on neither Recaulk nor clang-22, so no release cycle) |
| Sparkle, via shipyard | shipyard's `fetch_sparkle_framework.sh`, pinned by hash there | ❌ untrackable here: shipyard owns that pin | follows shipyard |
| `tests/fixtures/libSystemWrapper-exports.txt` | committed | ❌ untrackable: a frozen record of what Wowfunhappy shipped | never bumped by a bot |

The MacPorts build fetches GitHub's tarball of `DIGEST`, verified by `TARBALL_SHA256`, so a native 10.9 build needs no git. Renovate moves `REF`+`DIGEST`, and `.github/workflows/pins-bot.yml` writes the hash on Renovate's branch after checking that the tarball is the commit's tree.

No upstream release notes: Recaulk is its own upstream; a MacPorts bump is an ingredient move, which the notes' Build ingredients section names.

drydock 0.2.1 or later is required: it accepts the archive padding left after a member's string table.

drydock's binary is universal (x86_64 and arm64), so it runs natively on the 10.9 box and on every CI runner.
