# Build ingredients

Everything baked into what Recaulk ships, and how a change to it reaches a release.

Recaulk is **its own upstream**: it is versioned `YYYYMMDD.N` and nothing external releases it.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Recaulk's own source (own upstream) | `UPSTREAM_VERSION`: the date of the newest source a release carries, bumped by hand | ❌ untrackable: nothing external releases it | bumping it on `main` is the decision to release |
| MacPorts macports-legacy-support | `components/macports-legacy-support/version` | ✅ `git-refs` (REF+DIGEST; the pins bot writes TARBALL_SHA256) | publishes a `.N+1` repackage |
| MacOSX10.9 SDK, CMake modules, packaging and signing scripts | `Mavergreen/shipyard@v1` | ✅ github-actions manager tracks the tag | `@v1` moves without the pin changing, so nothing repackages by itself |
| `drydock-macho-rewrite`, the forwarding layer's symbol renamer | `components/drydock/version`, extracted at build time from `drydock-<ver>-linux-x86_64.tar.gz` on Linux and `drydock-<ver>.pkg` on a Mac, verified against its release's `SHA256SUMS` | ✅ github-releases manager tracks `Mavergreen/drydock` | a bump repackages via the ingredient-bump workflow (drydock depends on neither Recaulk nor clang-22, so no release cycle) |
| clang22: the compiler, assembler, linker (`ld64.lld`) and archiver (`llvm-ar`) that build everything Recaulk ships, and the Mach-O readers the build and tests use | `components/clang22/version`; on Linux its archive is verified by `components/clang22/linux-sha256` | ✅ github-releases manager tracks `Mavergreen/clang-22`; the pins bot writes `linux-sha256` on Renovate's branch | builds and tests on the bump's branch, and does **not** repackage (see Conformance deviations, `release-input`) |
| Linux host GNU make (MacPorts' Makefile), and the updater's CMake and build tool | the runner's own (`ubuntu-latest`), unpinned; recorded in `build-info-release.txt` as `build-make`, `updater-cmake` and `updater-build-tool` | ❌ untrackable: the runner image provides them | a runner image bump can change them without a commit; exit: a pinned make and CMake for Linux hosts, which shipyard's queue tracks |
| Sparkle, via shipyard | shipyard's `fetch_sparkle_framework.sh`, pinned by hash there | ❌ untrackable here: shipyard owns that pin | follows shipyard |
| `tests/fixtures/libSystemWrapper-exports.txt` | committed | ❌ untrackable: a frozen record of what Wowfunhappy shipped | never bumped by a bot |

The MacPorts build fetches GitHub's tarball of `DIGEST`, verified by `TARBALL_SHA256`, so a native 10.9 build needs no git. Renovate moves `REF`+`DIGEST`, and `.github/workflows/pins-bot.yml` writes the hash on Renovate's branch after checking that the tarball is the commit's tree.

drydock 0.3.0 or later is required: it is the first release with a Linux archive, and 0.2.1 first accepted the archive padding left after a member's string table. Its pkg's binary is universal, so it runs natively on the 10.9 box and on a modern Mac.

clang22 builds Recaulk on every host, so the Linux build and a native build on 10.9 compile the same source with the same compiler. Its `llvm-ar --format=darwin` writes the archives: clang22's Linux archive has no `llvm-libtool-darwin`.

## Declared state

- upstream: UPSTREAM_VERSION
- macports-legacy-support: components/macports-legacy-support/version
- drydock: components/drydock/version

## Conformance deviations

- scheme: Recaulk is its own upstream (no one else's release to repackage), so it versions itself by date as YYYYMMDD.N with no -mavericks.N axis
- release-input:components/clang22/*: clang22 builds what Recaulk ships, but its pin is in neither `## Declared state` nor repackage-on-ingredient-bump.yml's paths. clang-22 repackages on every Recaulk release (it ships librecaulk.a), so a Recaulk release on a clang22 bump would have the two repos release each other forever. Cost: a clang22 bump changes Recaulk's bytes only at its next release for another reason, so the release that carries it does not say so. `tests/clang22-not-a-release-input.sh` holds this. Revisit when clang-22 no longer bundles Recaulk, or when shipyard can tell a repackage that only follows another's from one that starts a cycle.
- self-upstream-exclude:components/clang22/linux-sha256: the pins bot's digest of the clang22 Linux archive; an ingredient pin, not Recaulk's own code
- self-upstream-exclude:release-notes/**: release-note sources; not in the pkg
- self-upstream-exclude:comment-reasons: the conventions gate's comment config; not in the pkg
- self-upstream-exclude:.claude/**: an agent's settings for working in this repo; not in the pkg

## Upstream release notes

No upstream release notes: Recaulk is its own upstream, and a MacPorts bump is an ingredient move that the notes' Build ingredients section names.

## Releasing

A push or a pull request builds and tests and never publishes. Only a run on `main` publishes, and only
by dispatch: the nightly reconcile dispatches `release.yml` when `UPSTREAM_VERSION`, the MacPorts pin or
the drydock pin on `main` names a declared state that no release carries yet, or you can now:

    gh workflow run release.yml -R Mavergreen/recaulk --ref main

A dispatch on any other ref, like a push or a pull request (the pins bot pushes to Renovate's branch as the
pins-bot GitHub App, so its push starts the pull request's run that `main`'s required checks read), builds and
tests and never publishes.

A packaging-only re-release of the same declared state (a new `.N`):

    gh workflow run release.yml -R Mavergreen/recaulk --ref main -f repackage=true

A MacPorts bump dispatches that repackage by itself once it lands on `main`, which happens only after the
pins bot has filled `TARBALL_SHA256` on Renovate's branch. A drydock bump does the same. A clang22 bump does not
(`release-input`, above): it lands on `main` once the pins bot has filled `components/clang22/linux-sha256`.
