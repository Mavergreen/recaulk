#!/bin/sh
# platform: macOS-only -- stable-runner unit/archiving controls; no app/permission request
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sh "$ROOT/tests/helpers/workspace-context.sh" --self-test
