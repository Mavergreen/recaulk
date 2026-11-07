#!/bin/sh
# platform: host-agnostic
# spec: README.md "Tests" -- a runtime test builds on any host and runs on 10.9; RECAULK_TEST_PHASE says
#       which half (build, run, both) this run does. Unset, both on Darwin 13 and build elsewhere.
if [ -z "${RECAULK_TEST_PHASE:-}" ]; then
  _rel="${RECAULK_FAKE_UNAME_R:-$(uname -r)}"
  if [ "${_rel%%.*}" = 13 ] && { [ -n "${RECAULK_FAKE_UNAME_R:-}" ] || [ "$(uname -s)" = Darwin ]; }; then
    RECAULK_TEST_PHASE=both
  else
    RECAULK_TEST_PHASE=build
  fi
fi
case "$RECAULK_TEST_PHASE" in
  build|run|both) ;;
  *) echo "RECAULK_TEST_PHASE is '$RECAULK_TEST_PHASE': want build, run or both"; exit 1 ;;
esac

if [ "$RECAULK_TEST_PHASE" = run ]; then
  : "${RECAULK_BUILD:?the run phase needs RECAULK_BUILD, the build tree the build phase made}"
  # platform: canonical, so a path dyld reports for a program in it matches the one a test expects
  B="$(cd "$RECAULK_BUILD" && pwd -P)"
else
  . build/lib.sh
  B="$(recaulk_build_dir)"
fi
W="$B/work"
if [ "$RECAULK_TEST_PHASE" = run ] && [ -n "${RECAULK_INSTALLED:-}" ]; then
  T="$RECAULK_INSTALLED"
else
  T="$B/stage/usr/local/mavergreen/recaulk"
fi
[ -f "$T/lib/librecaulk.a" ] || { echo "not built: run sh build/build-lib.sh first"; exit 77; }
if [ "$RECAULK_TEST_PHASE" != run ]; then
  if [ -z "${SDK:-}" ]; then
    SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
  fi
  recaulk_tools
  FLAGS="$TARGET_FLAGS -isysroot $SDK"
  # platform: the make on a Mac's PATH may be a wrapper (pkgsrc's bmake); MacPorts' Makefile needs GNU make
  if [ "$(uname -s)" = Darwin ]; then MAKE=/usr/bin/make; else MAKE=make; fi
fi

compiling() {
  [ "$RECAULK_TEST_PHASE" != run ]
}

# spec: README.md "Tests" -- tbin NAME: where this test's program NAME is built, in test-bin/
tbin() {
  _tb_dir="$B/test-bin/$(basename "$0" .sh)"
  if compiling; then mkdir -p "$_tb_dir"; fi
  printf '%s/%s\n' "$_tb_dir" "$1"
}

# platform: a library stock 10.9 lacks would fail only on the guest, as a dyld abort, so check_loads
#           PROG... fails the build half unless each library is the system's, Recaulk's staged one
#           (reached through DYLD_LIBRARY_PATH) or beside the program
check_loads() {
  _cl_rc=0
  for _cl_p in "$@"; do
    _cl_bad="$("${OTOOL:-otool}" -L "$_cl_p" | sed 1d | awk '{ print $1 }' | grep -v \
      -e '^/usr/lib/' -e '^/System/Library/' -e '^/usr/local/mavergreen/recaulk/lib/' \
      -e '^@executable_path/' -e '^@loader_path/')" || :
    if [ -n "$_cl_bad" ]; then
      echo "FAIL: $_cl_p loads what stock 10.9 does not have: $(printf '%s ' $_cl_bad)"
      _cl_rc=1
    fi
  done
  return $_cl_rc
}

# spec: README.md "Tests" -- runtime_half: the build half ends here; what follows runs on 10.9
runtime_half() {
  if [ "$RECAULK_TEST_PHASE" = build ]; then
    echo "$(basename "$0"): built; its runtime half runs on the 10.9 guest"
    exit 0
  fi
}
