#!/bin/sh
# platform: host-agnostic -- fake runtime tests exercise tests/helpers/built.sh's phases and
#           tests/guest/run-runtime-tests.sh; nothing is compiled or executed as Mach-O
set -eu
cd "$(dirname "$0")/.."
# spec: README.md "Tests" -- the cases set the phase themselves; the build job's own must not leak in
unset RECAULK_TEST_PHASE
R="$PWD"
D="$(mktemp -d "${TMPDIR:-/tmp}/test-phases.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# spec: tests/helpers/built.sh -- a build tree with the one file it looks for
BT="$D/build"
mkdir -p "$BT/stage/usr/local/mavergreen/recaulk/lib"
: > "$BT/stage/usr/local/mavergreen/recaulk/lib/librecaulk.a"

# spec: README.md "Tests" -- a fake runtime test, in a fake repo whose tests/helpers is this repo's:
#       it builds when compiling, and says "ran" after runtime_half
F="$D/repo"
mkdir -p "$F/tests"
ln -s "$R/tests/helpers" "$F/tests/helpers"
ln -s "$R/tests/guest" "$F/tests/guest"
ln -s "$R/build" "$F/build"
cat > "$F/tests/fake.sh" <<'EOF'
#!/bin/sh
# platform: macOS-only -- a fake; runs on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  echo built > "$(tbin prog)"
fi
runtime_half
cat "$(tbin prog)"
echo ran
EOF

phase() {  # phase UNAME_R [VAR=VALUE...]: run the fake test, print its output
  _u="$1"; shift
  (cd "$F" && env RECAULK_BUILD="$BT" RECAULK_FAKE_UNAME_R="$_u" SDK=/nonexistent CL=/nonexistent "$@" sh tests/fake.sh 2>&1)
}

# spec: README.md "Tests" -- a modern Mac builds and never runs (no Rosetta): the build half passes, the run half is skipped
out="$(phase 25.0.0)" || bad "phase_default_is_build_off_10_9: exited non-zero: $out"
case "$out" in *"its runtime half runs on the 10.9 guest"*) ;; *) bad "phase_default_is_build_off_10_9: no build-phase message: $out" ;; esac
case "$out" in *ran*) bad "phase_default_is_build_off_10_9: ran the runtime half: $out" ;; esac

# spec: README.md "Tests" -- natively on 10.9 (Darwin 13) one run does both halves
rm -rf "$BT/test-bin"
out="$(phase 13.4.0)" || bad "phase_default_is_both_on_10_9: exited non-zero: $out"
case "$out" in *built*ran*) ;; *) bad "phase_default_is_both_on_10_9: want built then ran: $out" ;; esac

# spec: README.md "Tests" -- the guest has no shipyard and no SDK; the run phase needs neither, only RECAULK_BUILD
out="$(cd "$F" && env -i PATH=/usr/bin:/bin RECAULK_BUILD="$BT" RECAULK_TEST_PHASE=run sh tests/fake.sh 2>&1)" \
  || bad "run_phase_needs_no_shipyard: exited non-zero: $out"
case "$out" in *built*ran*) ;; *) bad "run_phase_needs_no_shipyard: want the built program run: $out" ;; esac

# spec: README.md "Tests" -- the run phase compiles nothing
rm -rf "$BT/test-bin"
out="$(cd "$F" && env -i PATH=/usr/bin:/bin RECAULK_BUILD="$BT" RECAULK_TEST_PHASE=run sh tests/fake.sh 2>&1)" \
  && bad "run_phase_compiles_nothing: passed with no built program: $out"

# spec: README.md "Tests" -- on the guest a skip is a failure, and the runner names the test
cat > "$F/tests/skips.sh" <<'EOF'
#!/bin/sh
runtime_half() { :; }
exit 77
EOF
out="$(cd "$F" && env RECAULK_BUILD="$BT" sh tests/guest/run-runtime-tests.sh tests/skips.sh 2>&1)" \
  && bad "skip_on_guest_fails: runner passed: $out"
case "$out" in *"FAIL tests/skips.sh"*77*) ;; *) bad "skip_on_guest_fails: want 'FAIL tests/skips.sh' with 77: $out" ;; esac

# spec: README.md "Tests" -- a hung test is killed at its bound and named, and the runner goes on to the next
cat > "$F/tests/hangs.sh" <<'EOF'
#!/bin/sh
sleep 30
EOF
cat > "$F/tests/passes.sh" <<'EOF'
#!/bin/sh
echo fine
EOF
start="$(date +%s)"
out="$(cd "$F" && env RECAULK_BUILD="$BT" RECAULK_GUEST_TEST_BOUND=1 sh tests/guest/run-runtime-tests.sh tests/hangs.sh tests/passes.sh 2>&1)" \
  && bad "bound_kills_and_names: runner passed: $out"
case "$out" in *"FAIL tests/hangs.sh (outlived 1 s)"*) ;; *) bad "bound_kills_and_names: want 'FAIL tests/hangs.sh (outlived 1 s)': $out" ;; esac
case "$out" in *"ok tests/passes.sh"*) ;; *) bad "bound_kills_and_names: the next test did not run: $out" ;; esac
[ $(( $(date +%s) - start )) -lt 10 ] || bad "bound_kills_and_names: took $(( $(date +%s) - start )) s; the hung test's sleep outlived the bound"

# spec: README.md "Tests" -- a test that exits 124 itself has failed, not outlived its bound
cat > "$F/tests/exits124.sh" <<'EOF'
#!/bin/sh
exit 124
EOF
out="$(cd "$F" && env RECAULK_BUILD="$BT" sh tests/guest/run-runtime-tests.sh tests/exits124.sh 2>&1)" \
  && bad "exit_124_is_not_a_hang: runner passed: $out"
case "$out" in *"FAIL tests/exits124.sh (exited 124)"*) ;; *) bad "exit_124_is_not_a_hang: want 'exited 124': $out" ;; esac

# spec: README.md "Tests" -- past the run's total budget, the tests left are named as not run, and fail
out="$(cd "$F" && env RECAULK_BUILD="$BT" RECAULK_GUEST_TEST_BOUND=1 RECAULK_GUEST_BUDGET=1 \
  sh tests/guest/run-runtime-tests.sh tests/hangs.sh tests/passes.sh 2>&1)" && bad "budget_names_what_did_not_run: runner passed: $out"
case "$out" in *"FAIL tests/passes.sh (not run: the run's 1 s budget is spent)"*) ;;
  *) bad "budget_names_what_did_not_run: want passes.sh named as not run: $out" ;; esac

# spec: README.md "Tests" -- a file whose text merely holds a runtime_half line (a heredoc) is not a
#       runtime test: the runner takes only tests marked (RECAULK_TEST_PHASE) on line 2
cat > "$F/tests/mentions.sh" <<'EOF'
#!/bin/sh
# platform: host-agnostic
cat <<'X'
runtime_half
X
exit 1
EOF

# spec: README.md "Tests" -- with no names, the runner runs every test that has a runtime half
phase 25.0.0 > /dev/null
out="$(cd "$F" && env RECAULK_BUILD="$BT" RECAULK_TEST_PHASE= sh tests/guest/run-runtime-tests.sh 2>&1)" \
  || bad "default_list_is_runtime_tests: runner failed: $out"
case "$out" in *"ok tests/fake.sh"*) ;; *) bad "default_list_is_runtime_tests: fake.sh not run: $out" ;; esac
case "$out" in *passes.sh*|*hangs.sh*|*mentions.sh*|*exits124.sh*) bad "default_list_is_runtime_tests: ran a test that is not a runtime test: $out" ;; esac

# spec: README.md "Tests" -- on the guest the tests run against the installed product, which must be the
#       build tree's: a runtime test sees RECAULK_INSTALLED as T, and an installed library that differs fails
IN="$D/installed"
mkdir -p "$IN/lib"
for f in librecaulk.a librecaulk-cxxabi-exports.a libRecaulkSystem.dylib; do
  printf '%s\n' "$f" > "$BT/stage/usr/local/mavergreen/recaulk/lib/$f"
  cp "$BT/stage/usr/local/mavergreen/recaulk/lib/$f" "$IN/lib/$f"
done
cat > "$F/tests/where.sh" <<'EOF'
#!/bin/sh
# platform: macOS-only -- a fake; runs on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
runtime_half
echo "T=$T"
EOF
out="$(cd "$F" && env RECAULK_BUILD="$BT" RECAULK_INSTALLED="$IN" sh tests/guest/run-runtime-tests.sh tests/where.sh 2>&1)" \
  || bad "installed_product_is_t: runner failed: $out"
out="$(cd "$F" && env RECAULK_BUILD="$BT" RECAULK_INSTALLED="$IN" RECAULK_TEST_PHASE=run sh tests/where.sh 2>&1)"
[ "$out" = "T=$IN" ] || bad "installed_product_is_t: a runtime test's T is not the installed product: $out"
printf 'stale\n' > "$IN/lib/libRecaulkSystem.dylib"
out="$(cd "$F" && env RECAULK_BUILD="$BT" RECAULK_INSTALLED="$IN" sh tests/guest/run-runtime-tests.sh tests/where.sh 2>&1)" \
  && bad "installed_must_be_the_build: runner passed with a stale installed libRecaulkSystem.dylib: $out"
case "$out" in *"libRecaulkSystem.dylib"*) ;; *) bad "installed_must_be_the_build: the stale library is not named: $out" ;; esac
case "$out" in *"ok tests/where.sh"*) bad "installed_must_be_the_build: ran the tests against a stale install: $out" ;; esac
rm -f "$F/tests/where.sh"

# spec: README.md "Tests" -- a program that needs a library stock 10.9 lacks fails the build half, by name
cat > "$D/otool" <<'EOF'
#!/bin/sh
printf '%s:\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n\t/opt/homebrew/lib/libx.dylib (compatibility version 1.0.0)\n' "$2"
EOF
chmod +x "$D/otool"
out="$(cd "$F" && env MAVERICKS_ROOT="$F" RECAULK_BUILD="$BT" RECAULK_FAKE_UNAME_R=25.0.0 SDK=/nonexistent OTOOL="$D/otool" \
  sh -c '. tests/helpers/built.sh; check_loads /some/prog' 2>&1)" \
  && bad "foreign_library_fails_build_phase: passed: $out"
case "$out" in *"/some/prog"*"/opt/homebrew/lib/libx.dylib"*) ;; *) bad "foreign_library_fails_build_phase: want the program and the library named: $out" ;; esac

cat > "$D/otool" <<'EOF'
#!/bin/sh
printf '%s:\n\t/usr/lib/libSystem.B.dylib (x)\n\t/System/Library/Frameworks/Security.framework/Versions/A/Security (x)\n\t/usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib (x)\n\t@executable_path/libfwd.dylib (x)\n' "$2"
EOF
out="$(cd "$F" && env MAVERICKS_ROOT="$F" RECAULK_BUILD="$BT" RECAULK_FAKE_UNAME_R=25.0.0 SDK=/nonexistent OTOOL="$D/otool" \
  sh -c '. tests/helpers/built.sh; check_loads /some/prog' 2>&1)" \
  || bad "stock_libraries_pass_build_phase: failed: $out"

[ "$fail" = 0 ] && echo "test phases OK"
exit "$fail"
