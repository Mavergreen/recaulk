#!/bin/sh
# platform: macOS-only -- sourced by the modern-Mac oracles, which build for the Mac they run on
# spec: SKILL.md "Rosetta: none, CI included" -- the arch comes from the hardware, never from trying:
#       hw.optional.arm64 is 1 on Apple Silicon (its first macOS is 11.0), even in a translated
#       process, and absent on Intel Macs and 10.9. Sets arch, floor, SDK and OFLAGS; needs recaulk_tools.
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || :)" = 1 ]; then arch=arm64; floor=11.0; else arch=x86_64; floor=10.9; fi
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
OFLAGS="--no-default-config --target=$arch-apple-macos$floor -mmacosx-version-min=$floor -isysroot $SDK -fno-objc-arc"
