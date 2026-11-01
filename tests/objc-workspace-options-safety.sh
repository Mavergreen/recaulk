#!/bin/sh
# platform: macOS-only -- invalid options-oracle inputs must fail before launch/API absence
set -eu
cd "$(dirname "$0")/.."
exec sh tests/objc-workspace-options.sh --self-test
