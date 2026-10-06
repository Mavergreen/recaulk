# Recaulk

Drydock gives a binary a recaulk. Mac OS X 10.9's libSystem lacks functions that binaries built against a
modern SDK expect. Recaulk fills those gaps: MacPorts'
[macports-legacy-support](https://github.com/macports/macports-legacy-support), fetched unmodified at a
pinned commit, plus Wowfunhappy's 10.9 shims.

## Artifacts

`build/build-lib.sh` builds them for `/usr/local/mavergreen/recaulk/`:

- `lib/librecaulk.a`: MacPorts' objects and our back-fills. Link it with
  `-isystem /usr/local/mavergreen/recaulk/include/recaulk -L/usr/local/mavergreen/recaulk/lib -lrecaulk
  -framework CoreFoundation -framework Security -framework CoreServices -framework IOKit -lobjc`.
- `lib/libRecaulkSystem.dylib`: re-exports 10.9's libSystem and carries the back-fills and overrides.
  This is what drydock points adapted binaries at.
- `include/recaulk/`: MacPorts' headers plus ours.

## Credits

Recaulk is MacPorts' work and Wowfunhappy's, packaged and extended here; `PROVENANCE.md` records what
came from where. This is an unofficial community build, not affiliated with MacPorts.

## Install (once)

This repo builds with [shipyard](https://github.com/Mavergreen/shipyard),
the family's shared CMake helpers. Install its pkg once:

```sh
gh release download -R Mavergreen/shipyard --pattern '*.pkg'
sudo installer -pkg mavericks-shipyard-*.pkg -target /
```

That puts `shipyard-cmake`, `shipyard-ctest` and `shipyard-cpack` in
`/usr/local/mavergreen/bin` (on the path via `/etc/paths.d/mavergreen`).
**`shipyard-cmake` is the only cmake that configures this
project.** It finds shipyard in its own prefix, so `find_package(MavericksShipyard)`
resolves with nothing to register and no `CMAKE_PREFIX_PATH` to set, and
`MavericksShipyardConfig.cmake` refuses any other cmake by name rather than
half-working. Do not clone, vendor or submodule shipyard.

CI does the same thing through `Mavergreen/shipyard/.github/actions/install@v1`.

To build the updater .app by hand:

```sh
. build/msc.sh   # exports SHIPYARD_SCRIPTS, for MavericksToolchain.cmake below
shipyard-cmake -S . -B "${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/recaulk-updater" -DCMAKE_OBJC_COMPILER=/usr/bin/clang \
  -DCMAKE_TOOLCHAIN_FILE="$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake"
shipyard-cmake --build "${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/recaulk-updater" --target recaulk-updater
```

`tests/updater-build.sh` and `tests/package-pkg.sh` skip (exit 77) when
`shipyard-cmake` is not installed, since without it nothing here can be
configured.

If you are developing shipyard itself, install your working copy to a prefix of
your own and point one configure at it — shipyard's own README has the details:

```sh
export CMAKE_PREFIX_PATH="$HOME/.local/opt/shipyard-dev"
. build/msc.sh   # exports SHIPYARD_SCRIPTS, from the same dev prefix
shipyard-cmake -S . -B "${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/recaulk-updater" -DCMAKE_TOOLCHAIN_FILE="$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake"
```
