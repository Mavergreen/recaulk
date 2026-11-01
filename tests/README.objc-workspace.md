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
The mixed-URL case likewise refuses any pre-existing sentinel.txt, including
linked files, and exclusively creates its fixture file before invoking the API.

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
permission skip or a broad waiver. The direct CLI does not request a grant.
The explicit stable-context path below hosts the same current implementation
inside a dedicated sender app. Do not approve Terminal/PiG or unrelated apps
as a shortcut. The successful consented native research matrix is separate
contract evidence, not a passing execution of this whole suite.

The oracle remains a partial foundation until the prepared execution identities
are approved, ordinary scoped consent is established, all native cases are
actually executed under that context, and independent review is completed. Architecture coverage is host-only where no
alternate execution capability exists. Ownership tests measure explicit caller
retains across a pool, not internal retain/autorelease counts. Nonactivation is
a final-state observation, not a transient-activation proof. Bounded observation
deadlines and partial JSONL states are not quiescence proofs.

## Additional native option measurements (not provider acceptance)

`sh tests/objc-workspace-options.sh --native --report NEW_DIR` compiles a separate
controller against the unchanged probe source. It does not load a provider,
register a method, request consent or use/re-sign the stable context. The only
app it may select is its new private `REPORT_DIR/Probe.app`; ordinary ad-hoc
signing applies only to that fresh fixture. Input source hashes and the fixture
executable/plist hashes are retained, with post-run verification.

The 14 cases cover the real webbrowser call shape (Default, empty dictionary,
one URL), multiple/interleaved files and URLs, recording-only print, Hide,
WithoutActivation, WithoutAddingToRecents, empty arrays, async return identity,
worker-thread calls and selected malformed inputs. No caller event loop runs
during the API call itself. Worker invocation uses a join; this is not a bound
on the OS call's latency. Record collection and cleanup remain bounded.

Assertions on valid nonempty calls require exact returned fixture identity and
complete returned-PID payload evidence. The print waiter requires **every**
expected file, not merely the first print callback. Group sizes/order, immediate
async state and malformed-input outcomes are observations, not newly promised
API behavior. Hide waits for finish and a bounded final hidden-state check;
nonactivation remains final-state-only. Empty/error outcomes retain side effects.

Recents queries are read-only. Only matching private app/document counts and
unresolved counts are retained; unrelated history is never logged, lists are
never edited/reset, and resolution cannot mount volumes or display UI. Missing
lists or absence without an observable positive control do **not** prove recents
suppression. The without-recents case is explicitly observed-only in this unchanged native
controller. The separate public-floor controls below provide an observable
positive control for the implementation decision. HideOthers and error-panel UI are not executed. Nil target
URLs are not automatically tested because they could select a real default app.

`sh tests/objc-workspace-options-safety.sh` checks rejection of out-of-report private apps,
unknown cases, existing/linked output and regular/symlink/hardlink sentinels
before invocation or absence handling. `sh tests/objc-workspace-options-observation.sh`
uses a real gated writer to prove split print batches are fully awaited. Its
optional `--mutation-check` deliberately changes a temporary observer copy to
return after the first print callback; expected exit is 1, not a passing suite.

A Mavericks exit 77 is only valid API absence, **not** native option acceptance.
Those reference inputs must still be kept separate from newer implementation
source. Do not use this newer checkout with the approved source-bound context.
Verified native evidence contains eight asserted passes/six observation-only
option cases and 15 asserted passes/six observation-only original cases. It is
not a claim that a provider exists or that observation-only cases became passes.

## Approved public-floor Recents refinement

The old URL-based launcher plus manually queued events delivered files but did
not update document Recents during the checked interval. The old public
bundle-ID URL-opening API supplied a working SAME-HOST positive control, but
cannot replace exact selected-PID/configuration behavior in the provider.
The maintainer approved supplemental public-API requested-file bookkeeping.

`sh tests/objc-workspace-recent-decisions.sh` uses the REAL research helper with
recording CoreServices boundaries: no shared list or preference is edited.
Checks include disabled limit0, WithoutAddingToRecents, browser-only no-access,
unknown/missing preference, unavailable list, partial failure and optional
error output. Its `--mutation-check` breaks only a temporary copy's zero-limit
guard; expected exit1 proves the disabled-preference assertion is effective.
These are decision/characterization tests, not native failure-mode acceptance.

Explicit real-Mavericks reproduction (NEW physical absolute report path):

```
RECAULK_WORKSPACE_RECENTS_PROBE=1 sh tests/objc-workspace-recent-controls.sh /private/tmp/NEW_PRIVATE_REPORT
```

This opt-in RESEARCH experiment creates fresh controlled recording fixtures;
ordinary launch effects and public LSSharedFileListInsertItemURL record only
requested files. Default cases compare two-file launch+bookkeeping against the
old public URL-opening control; WithoutAddingToRecents; worker-thread delivery
without a caller loop; and print-event recording against the old public print
control. No real printing, external app/default handler, permission request,
history reset/removal or preference change. Normal public insertion enforces
the observed system capacity and can naturally evict oldest items, just as the
URL-opening control does. No explicit removal API is used.

No-argument ordinary suite discovery emits an explicit unmeasured/SKIP without
opt-in; direct invocations without opt-in FAIL. A disabled/unreadable positive
control is cannot-measure/failure, never a request to enable history. The
read-only observer matches path/reference strings generated ONLY from known
private files; unrelated candidate paths are never resolved or logged. Its
unresolved count stays explicit. Snapshot seeds/counts distinguish a changing
list from merely failing to recognize an opaque item. Observations are bounded,
not a quiescence or universal ordering guarantee. Every fixture input is hashed
before/after and cleanup is checked.

These tests do not register the missing method. Production implementation,
activation, genuine method-based delivery and modern preservation tests remain
separate acceptance gates. The research helper's explicit error on unknown or
failed bookkeeping is an implementation decision, not an induced native error
experiment. Partial side effects are not rolled back by clearing history.

## Unregistered backend unit gate

`sh tests/objc-workspace-backfill-unit.sh` compiles the actual MRC backend,
event planner and public Recents implementation. Per-call recording operations
exercise launch/lookup/send/bookkeeping failures without launching an app or
editing history. The production Recents implementation is additionally compiled
against recording CoreServices boundaries, NOT substituted with the research
helper, to exercise disabled/missing preferences and partial failures.

Coverage includes caller config/event copies, four documented configuration
keys and unknown keys, unchanged flag bits, all-file odoc/pdoc grouping, exact
PID addressing, custom initial event, missing/wrong reacquisition, empty-array
failure after launch, observed invalid-member/relative-URL handling, optional
error output, and caller-retained +0 objects/errors across a pool boundary.
Reuse argv/environment semantics remain delegated to the public launcher and
are checked by actual native/floor integration, not by asserting a fake OS model.

This does NOT register a method or build/link a companion archive. These tests
are not external delivery, activation, modern preservation or Codex sign-in
acceptance. No new sender permission is requested or inherited.

## Stable app-hosted context

Use physical absolute paths. Preparation does not launch the pair or query/request
Automation permission. Verification never silently rebuilds signed inputs.
Commit source before preparing identities intended for approval:

```
sh tests/objc-workspace-reference.sh --prepare-context /private/tmp/NEW_CONTEXT
sh tests/objc-workspace-reference.sh --verify-context /private/tmp/NEW_CONTEXT
```

A context contains fixed Sender.app, Probe.app and unsigned events/. Both apps
are ad-hoc signed once. Source fingerprint/commit, host architecture, compiler,
explicit pinned SDK identity, app-tree hashes, signing details and absolute
paths are recorded in the context. Moving it, changing source/commit/build inputs
or modifying any signed app file makes verification fail. No auto-update or
permission-reset operation is provided. Source changes require a deliberately
prepared context and a fresh identity review, not silent re-signing.

**Only after exact identity approval**, the explicit authorization interface is:

```
sh tests/objc-workspace-reference.sh --authorize-context CONTEXT --report NEW_DIR
```

This launches Sender.app through NSWorkspace, not direct execution of its Mach-O.
Only that app runs the public permission query/request against its verified
private Probe.app. A new ordinary prompt must be approved manually; a denial or
unexpected requesting identity is a blocker, not permission to reset policy.
`permission-before.json` records the nonprompting preflight and actor identity
before the sole requesting branch. Authorization tests status, not delivery.
Preparation tests never invoke this operation.

Nonprompting status or full execution (reports must be new and outside CONTEXT):

```
sh tests/objc-workspace-reference.sh --preflight-context CONTEXT --report NEW_DIR
sh tests/objc-workspace-reference.sh --context CONTEXT --report NEW_DIR
RECAULK_WORKSPACE_CONTEXT=CONTEXT sh tests/objc-workspace-reference.sh --report NEW_DIR
RECAULK_WORKSPACE_CONTEXT=CONTEXT MAVERICKS_TEST_JOBS=4 sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"
```

The environment variable selects the app-hosted path for the auto-discovered
reference test only. No context means the existing direct behavior, including
strict custom-delivery failures rather than a skip. Context execution without
permission fails nonzero/cannot-measure and does not prompt. Even permission
status zero is insufficient: a no-prompt, nonce-bearing external transport
control must deliver the exact payload before any native case is accepted.

All 21 current cases run serially via the actual reference main compiled into
the sender. They keep CONTEXT as REPORT_DIR and CONTEXT/Probe.app as APP_URL.
Each case has fresh URL/custom payload nonces and exact existing assertions.
After closed output and verified fixture cleanup, controller.json/events and
known mixed sentinel are moved into NEW_DIR/CASE/, then an empty unsigned
events directory is recreated. Signed plist/output paths never rotate. Archived
metadata retains original paths, including file-URL referents. Events are bounded
observations, not quiescence. Six observational cases remain observational.

A context run lock refuses overlap; it is never broken using a PID log. Unknown
or unarchived state fails rather than being replaced. Actor exit, missing/partial
JSON, source mismatch, timeout and interruption fail. The launcher forwards
signals only after checking the running sender bundle identity; sender and
launcher cleanup target only verified fixture/sender bundle URLs. Partial
failed state may deliberately block a later run until reviewed; no broad or
automatic destructive recovery is offered. SIGKILL/same-user races are not a
sandbox guarantee. The existing bounded signal limitations still apply.

Modern contexts use the pinned 11.3 SDK: arm64/min 11.0, or native x86_64/min
10.14 with that SDK explicitly selected for public no-prompt support. The direct
floor controller remains x86_64/10.9. Context unit controls compile against the
host floor pin; modern preparation integration skips where no-prompt APIs cannot
be tested. No Rosetta installation is required.

`objc-workspace-context-test.sh` exercises lock/archive/stale-response logic and
fixture-free unit actors (exit/interruption), not the native API contract.
`objc-workspace-context-prepare.sh` prepares a disposable unique pair, verifies
immutability/output/lock/tamper refusal and an ungranted nonprompt failure. It
never asks for consent, and does not establish whole-oracle native GREEN.
