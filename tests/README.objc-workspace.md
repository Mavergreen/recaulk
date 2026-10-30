# Native NSWorkspace reference tests (partial foundation)

Run `sh tests/objc-workspace-reference.sh [--report NEW_DIR]` with
`SHIPYARD_SCRIPTS` selecting the pinned shipyard scripts. Host architecture and
SDK selection are explicit. No Recaulk implementation is loaded.

`--report` claims a new private directory, never reuses output, and rejects
symlink components. Use physical `/private/tmp` or `/private/var` spellings for
that option. Default temporary mode deliberately retains the native lexical
TMPDIR spelling so `/var` to `/private/var` file delivery remains exercised.

The standalone interface is `reference CASE APP_URL REPORT_DIR`. REPORT_DIR must
already exist, be owned by the caller and private (no group/other permissions).
Its `controller.json` must not exist. The controller reserves that file using
exclusive/no-follow creation and writes through its descriptor, including on
failure or method absence. It will not replace an existing file or symlink.

The only accepted app is the controlled `REPORT_DIR/Probe.app`, with local file
URL/path, no query/fragment or remote file host, CFBundleExecutable
`WorkspaceProbe`, APPL package type, and an `org.mavergreen.` bundle ID. Its
Info.plist must point WorkspaceProbeReportDirectory at REPORT_DIR/events.
App, plist, executable and events symlinks are refused. Root-owned standard
`/var -> /private/var` and `/tmp -> /private/tmp` aliases are the only path-walk
exceptions, preserving lexical-path regression coverage. These checks protect
accidental/hostile inputs; they are not a sandbox against a same-user adversary
who can concurrently mutate the caller's own private directories or binaries.

Exit 0 means documented assertions passed or an explicitly observed-only case
was recorded; 1 means failure/cannot-measure; 77 means valid prerequisites but
no native system method. Unknown cases and invalid prerequisites fail before
absence handling. Unsafe output paths fail on stderr without writing elsewhere.

INT, TERM and HUP are caught by the controller using an async-signal-safe flag.
It stops polling, marks evidence incomplete, and cleans only running applications
whose bundle URL matches its verified fixture. Cleanup completion is bounded
and checked. The shell forwards signals to its own controller child and waits
before temporary cleanup. Tests cover each signal after fixture startup through
both entry points, under ordinary signal dispositions. SIGKILL and externally
inherited ignored shell signals are not recoverable by shell traps; interruption
during every possible launch/late-side-effect boundary is not claimed covered.

## Contract and permission boundary

Documented custom-event startup (`custom-event`) and reuse (`custom-reuse`) now
use nonempty URLs and require the exact URL/custom payload at the verified
returned PID. This follows the coordinator's evidence-backed contract ruling.
`empty` and `empty-custom` are separate observation-only cases, preserving nil
returns/errors and process/event side effects rather than inventing success.

Custom Apple-event delivery requires an established execution/transport context.
The rotating CLI fixtures do **not** inherit permission granted to the separate,
stable research sender/fixture pair. Missing delivery remains failure, never a
permission skip or a broad waiver. This CLI does not request a grant or implement
a reusable consent-aware sender. Do not approve Terminal/PiG or unrelated apps
as a shortcut. The successful consented native research matrix is separate
contract evidence, not a passing execution of this whole suite.

The oracle remains a partial foundation until that reusable execution path and
independent review are completed. Architecture coverage is host-only where no
alternate execution capability exists. Ownership tests measure explicit caller
retains across a pool, not internal retain/autorelease counts. Nonactivation is
a final-state observation, not a transient-activation proof. Bounded observation
deadlines and partial JSONL states are not quiescence proofs.
