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

drydock 0.2.1 or later is required: it accepts the archive padding left after a member's string table.

drydock's binary is universal (x86_64 and arm64), so it runs natively on the 10.9 box and on every CI runner.

## Declared state

- upstream: UPSTREAM_VERSION
- macports-legacy-support: components/macports-legacy-support/version
- drydock: components/drydock/version

## Conformance deviations

- scheme: Recaulk is its own upstream (no one else's release to repackage), so it versions itself by date as YYYYMMDD.N with no -mavericks.N axis
- rosetta:.github/workflows/release.yml: the release job runs on an Apple Silicon (arm64) runner and primes Rosetta ("Ensure this runner can run x86_64 (Rosetta)") so `tests/load.sh`, `tests/shim-tests.sh`, `tests/macports-own.sh`, `tests/forward-runtime.sh` and `tests/forward-abi.sh`, and the `x86_64_runs` probe they gate on, can execute the shipped x86_64 code (librecaulk.a and libRecaulkSystem.dylib linked into test programs) before it ships. It cannot run natively there: the code under test is the shipped x86_64 build, and the release runner is arm64 with no Intel runner to use instead. CI runs these tests, it does not skip them; native 10.9 runs them natively. Reconsider when they can move to an x86_64 host (the 10.9 box or the Mavericks VM runner the family is bringing to GitHub Actions); at the latest before macOS 28 removes Rosetta.

## Upstream release notes

No upstream release notes: Recaulk is its own upstream, and a MacPorts bump is an ingredient move that the notes' Build ingredients section names.

## Releasing

A push or a pull request builds and tests and never publishes. Only a run on `main` publishes, and only
by dispatch: the nightly reconcile dispatches `release.yml` when `UPSTREAM_VERSION`, the MacPorts pin or
the drydock pin on `main` names a declared state that no release carries yet, or you can now:

    gh workflow run release.yml -R Mavergreen/recaulk --ref main

A dispatch on any other ref (the pins bot dispatches one on each Renovate branch) builds and tests and
never publishes.

A packaging-only re-release of the same declared state (a new `.N`):

    gh workflow run release.yml -R Mavergreen/recaulk --ref main -f repackage=true

A MacPorts bump dispatches that repackage by itself once it lands on `main`, which happens only after the
pins bot has filled `TARBALL_SHA256` on Renovate's branch. A drydock bump does the same.
