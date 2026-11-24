# wait_result_prepost proof kit

For a disposable 10.9.5 guest on kernel 13F1911 (`kern.uuid` 8926E512-6714-34FC-B27C-6AE90EB51D5E), with
two or more CPUs, run as root. It proves Recaulk's `wait_result_prepost` kernel fix, which needs three things:

1. Without any fix, the bug: an untimed `kevent` returns 0 events, and a crash repro panics
   `kqueue_scan_continue: - invalid wait_result (3)`.
2. With only the backstop (`kqueue_scan_restart`), the panic becomes `EBADF` and is logged. The silent bug stays.
3. With both, neither happens.

`kfix_wait_result` is the reproducer: a waiter thread leaves a known `wait_result` behind, then calls `kevent`
with no timeout while a sender thread's Mach message lands in the window. The `-plain` steps race it without
DTrace for a bounded time. The `-dtrace` steps widen the window with `dtrace -w` (`chill` at
`fbt::wait_queue_assert_wait_with_leeway:entry`) and record the `wait_result` every fast-path wait leaves.

Every step prints lines starting `PASS`, `FAIL`, `EXPECTED` (the bug, shown as it should be in that
configuration), `INCONCLUSIVE` or `INFO`. Relay them as they are.

It never unloads or replaces the installed Recaulk, its KPI kext or macFUSE. The test kext loads from the kit's
own copy, and a reboot removes it from the kernel. The kit writes only inside its own directory.

## Steps

The kit runs across five boots. `/tmp` is emptied at every boot, so the kit lives in `/var/tmp/kfix-wr`.

**1. Copy it in** (once, from the share; nothing is ever written back to the share):

    sudo rm -rf /var/tmp/kfix-wr && sudo cp -R /path/on/share/kfix-wr /var/tmp/kfix-wr
    cd /var/tmp/kfix-wr && shasum -a 256 -c SHA256SUMS

Every line must say `OK`.

**Boot A: no fix.** On a fresh boot, with nothing loaded by hand:

2. `sudo sh run.sh preflight`: every line PASS, and configuration `nofix`.
3. `sudo sh run.sh dtrace-check`: PASS, or INCONCLUSIVE, after which skip every `-dtrace` step and the `probe` step.
4. `sudo sh run.sh silent-plain`: EXPECTED (the bug without DTrace), or INCONCLUSIVE (the window was not hit in 2 minutes).
5. `sudo sh run.sh silent-dtrace`: EXPECTED.
6. `sudo sh run.sh probe`: EXPECTED, or INCONCLUSIVE.
7. `sudo sh run.sh restart-plain`: **the guest should panic here.** Note the panic text on the console, then
   reset the guest. If it prints INCONCLUSIVE instead (no panic), go to step 9 in this same boot.

**Boot B: classify, then the widened crash.**

8. `sudo sh run.sh classify`: EXPECTED (ours: `invalid wait_result (3)` with `kqueue_scan` frames). Any other
   panic prints INCONCLUSIVE: "probe-induced or unrelated", and the run proves nothing.
9. `sudo sh run.sh restart-dtrace`: **the guest should panic here.** Reset it.

**Boot C: classify, then the backstop alone.**

10. `sudo sh run.sh classify`: EXPECTED.
11. `sudo sh run.sh load-backstop`: PASS, configuration `backstop`.
12. `sudo sh run.sh silent-plain`, then `silent-dtrace`, then `probe`: the same as steps 4 to 6. The backstop
    leaves the silent bug alone.
13. `sudo sh run.sh restart-plain`, then `restart-dtrace`: EXPECTED (`EBADF` instead of a panic, and the panic's
    message in `dmesg`), or INCONCLUSIVE (no `EBADF` in the window). It must not panic. If it does, that is a FAIL:
    reset, run `classify`, and report both.
14. Reboot. The test kext refuses to unload once applied.

**Boot D: both fixes.**

15. `sudo sh run.sh load-both`: PASS, configuration `both`.
16. `sudo sh run.sh silent-plain`, `silent-dtrace`, `probe`, `restart-plain`, `restart-dtrace`: each PASS.
17. Reboot.

**Boot E: leave the guest as it was.**

18. `sudo sh run.sh cleanup`: PASS. No RecaulkKernelFixes is loaded, and the Recaulk pkg version is the one
    preflight recorded. It removes `/var/tmp/kfix-wr`. The guest is back on Recaulk's released pkg, its KPI kext
    and macFUSE, untouched.

## Timing

The defaults are sized for an emulated (QEMU TCG) guest. The environment variables below override them.

| Variable | Default | What it sets |
| --- | --- | --- |
| `KFIX_WR_SECONDS` | 120 | Each `-plain` and `probe` run |
| `KFIX_WR_ITERATIONS` | 20 | Each `-dtrace` run |
| `KFIX_WR_DELAY_US` | 10000 | How long after the waiter starts `kevent` the sender sends |
| `KFIX_WR_CHILL_NS` | 40000000 | How long DTrace holds the waiter at the wait |
| `KFIX_WR_RANDOM_US` | 1000 | The `-plain` and `probe` runs pick the sender's delay at random below a hundredth, a tenth or all of this |

The delay must be longer than the waiter's way from `kevent` to the wait, and shorter than the chill. If a
`-dtrace` step says the message never landed in the window, run it again with a larger chill or a smaller
delay, for example `sudo KFIX_WR_CHILL_NS=80000000 KFIX_WR_DELAY_US=5000 sh run.sh silent-dtrace`. DTrace
allows about half a second of chill per second.

Logs, the DTrace program and any copied panic report are in `/var/tmp/kfix-wr/state`.
