/*
 * kevent64_shim.c -- MavericksLegacySupport libSystem shim.
 * Split verbatim from the former modern_api_polyfills.c; the shared DBG
 * helper and common includes live in mav_shim_debug.h.
 */
#include "mav_shim_debug.h"

/* ── kevent64 shim: 10.9's kqueue doesn't know KEVENT_FLAG_ERROR_EVENTS or
 * KEVENT_FLAG_IMMEDIATE (both added in 10.10), so when uSockets calls
 * kevent64(kq, changes, n, changes, n, FLAG=0x2, NULL) expecting "only return
 * EV_ERROR events, then return immediately", 10.9 instead:
 *
 *   (a) returns any ready event (e.g. a just-registered writable socket's
 *       EVFILT_WRITE fire). uSockets discards those returns, and because it
 *       registered with EV_ONESHOT the event is consumed and never re-fires
 *       — the main loop never learns the socket is writable, and the HTTP
 *       client sits there for 4 seconds until timing out.
 *
 *   (b) BLOCKS FOREVER when no events are ready (e.g. registering a fresh
 *       timer whose deadline is in the future). Without FLAG_ERROR_EVENTS
 *       semantics and with NULL timeout, kevent64 waits until any event
 *       arrives on the kqueue. uSockets expects the call to return as soon
 *       as the changes are submitted; instead the main thread pins here
 *       forever, starving the event loop. This is the "idle for a few
 *       minutes, next request hangs" symptom — a JS setTimeout or
 *       undici pool timer registers during the quiet window, hits this
 *       path with nothing to fire, and parks the loop.
 *
 * Fix: handle (a) by setting EV_RECEIPT on every change, which 10.9 does
 * support: the kernel answers each change with an EV_ERROR receipt (data 0 on
 * success) and leaves ready events queued for the next wait, where they are
 * reported as usual — or discarded by the kernel if the fd is closed first.
 * Handle (b) by forcing a zero timeout on the real call whenever
 * FLAG_ERROR_EVENTS is set — that's what modern kqueue does natively when
 * the flag is present, regardless of what the caller passes in `timeout`. */
#define KEVENT_FLAG_ERROR_EVENTS 0x2
#define KEVENT_FLAG_IMMEDIATE    0x1

extern int kevent64(int kq, const struct kevent64_s *changelist, int nchanges,
                    struct kevent64_s *eventlist, int nevents,
                    unsigned int flags, const struct timespec *timeout);
int kevent64_wrapper(int kq, const struct kevent64_s *changelist, int nchanges,
                     struct kevent64_s *eventlist, int nevents,
                     unsigned int flags, const struct timespec *timeout) __asm("_kevent64");

/* DIAGNOSTIC: when MAV_KQ_TRACE=/path is set, log registrations, mach-port
 * translation and socket()/connect() to that file. Zero-cost when unset. */
static FILE *g_trace = NULL;
static int   g_trace_ready = 0;
static pthread_mutex_t g_trace_mu = PTHREAD_MUTEX_INITIALIZER;
static void trace_init(void) {
    if (g_trace_ready) return;
    g_trace_ready = 1;
    const char *p = getenv("MAV_KQ_TRACE");
    if (!p || !*p) return;
    g_trace = fopen(p, "a");
    if (g_trace) setvbuf(g_trace, NULL, _IOLBF, 0);
}
static void tlog(const char *fmt, ...) {
    if (!g_trace) return;
    pthread_mutex_lock(&g_trace_mu);
    struct timeval tv; gettimeofday(&tv, NULL);
    va_list ap; va_start(ap, fmt);
    fprintf(g_trace, "%ld.%06d ", (long)tv.tv_sec, tv.tv_usec);
    vfprintf(g_trace, fmt, ap);
    va_end(ap);
    fputc('\n', g_trace);
    pthread_mutex_unlock(&g_trace_mu);
}

/* Drain a mach port that kevent64 just reported EVFILT_MACHPORT on.
 *
 * Bun registers EVFILT_MACHPORT with fflags=MACH_RCV_MSG|MACH_RCV_OVERWRITE,
 * expecting the kernel to dequeue the message into event.ext[0] as a
 * side-effect of kevent64 delivery. Modern kernels honour that. The 10.9
 * kernel appears not to — the port's 1-slot queue stays populated after
 * the fire. Bun's us_internal_accept_poll_event is a no-op on kqueue,
 * so nobody else drains either.
 *
 * Consequence: after the first wakeup on `loop->data.wakeup_async`, the
 * port remains full forever. Every subsequent us_internal_async_wakeup
 * (which sends with MACH_SEND_TIMEOUT=0) returns MACH_SEND_TIMED_OUT,
 * which Bun silently treats as "already pending"; no new EVFILT_MACHPORT
 * fire occurs because the port is level-triggered on new messages, and
 * the HTTP client thread parks in kevent64 forever. This is precisely
 * the "first prompt works, second prompt hangs after idle" symptom.
 *
 * Fix: after kevent64 returns an EVFILT_MACHPORT event, do a non-
 * blocking mach_msg(MACH_RCV_MSG|MACH_RCV_TIMEOUT, 0) on that port to
 * actually dequeue the message. We discard the payload — Bun never
 * inspects it either (it's purely a wakeup signal). The port's queue
 * is now empty, so the next sender's mach_msg succeeds and triggers a
 * fresh EVFILT_MACHPORT fire.
 *
 * Buffer size: Bun uses MACHPORT_BUF_LEN = 1024. Use the same here so
 * MACH_RCV_TOO_LARGE doesn't leave the message stuck. */
/* Port → portset lookup for EVFILT_MACHPORT translation. Bun creates
 * one wakeup port per loop; current Bun allocates exactly one async.
 * 32 slots leave headroom for future asyncs / multiple loops without
 * needing a hash table. Linear scan is trivial at this size. */
/* Sized for concurrency, not lifetime: entries are released as their one-shot
 * fires (see mp_release_by_pset), so this only has to cover lookups in flight
 * at the same instant. Bun issues ~5 per fetch and subagents can fetch in
 * parallel, so leave generous headroom — an entry is 12 bytes. */
#define MP_MAP_SIZE 128
static struct {
    mach_port_t port;   /* original receive port Bun registered */
    mach_port_t pset;   /* portset we created to wrap it */
    int no_drain;       /* 1 = caller receives the msg itself (don't consume it) */
} g_mp_map[MP_MAP_SIZE];
static pthread_mutex_t g_mp_mu = PTHREAD_MUTEX_INITIALIZER;

/* Tear down one map slot: pull the port back out of our portset and drop the
 * portset right. Caller must hold g_mp_mu. The port itself is untouched — we
 * never owned it, and messages already queued on it stay queued (a portset
 * routes notifications; it doesn't hold the messages). */
static void mp_release_locked(int i) {
    mach_port_t self = mach_task_self();
    if (g_mp_map[i].port != MACH_PORT_NULL)
        mach_port_move_member(self, g_mp_map[i].port, MACH_PORT_NULL);
    if (g_mp_map[i].pset != MACH_PORT_NULL)
        mach_port_mod_refs(self, g_mp_map[i].pset, MACH_PORT_RIGHT_PORT_SET, -1);
    tlog("MACHPORT-RELEASE port=%u pset=%u no_drain=%d",
         (unsigned)g_mp_map[i].port, (unsigned)g_mp_map[i].pset, g_mp_map[i].no_drain);
    g_mp_map[i].port = MACH_PORT_NULL;
    g_mp_map[i].pset = MACH_PORT_NULL;
    g_mp_map[i].no_drain = 0;
}

/* True once the mapped name no longer names a live receive right — the owner
 * destroyed it, so the cached portset is useless. */
static int mp_port_dead(mach_port_t port) {
    mach_port_type_t t = 0;
    if (mach_port_type(mach_task_self(), port, &t) != KERN_SUCCESS) return 1;
    return (t & MACH_PORT_TYPE_RECEIVE) == 0;
}

/* Mach port *names* are recycled. A name can therefore be live yet refer to a
 * different port than the one we wrapped — in which case it is not a member of
 * our portset and registering on that portset would never fire. Verifying
 * membership is what makes a cache hit trustworthy. */
static int mp_is_member(mach_port_t pset, mach_port_t port) {
    mach_port_name_array_t members = NULL;
    mach_msg_type_number_t count = 0;
    if (mach_port_get_set_status(mach_task_self(), pset, &members, &count) != KERN_SUCCESS)
        return 0;
    int found = 0;
    for (mach_msg_type_number_t i = 0; i < count; i++)
        if (members[i] == port) { found = 1; break; }
    if (members)
        vm_deallocate(mach_task_self(), (vm_address_t)members,
                      count * sizeof(*members));
    return found;
}

/* Caller must hold g_mp_mu. Returns the slot index or -1. Releases the slot if
 * the cached mapping has gone stale. */
static int mp_find_valid_locked(mach_port_t port) {
    for (int i = 0; i < MP_MAP_SIZE; i++) {
        if (g_mp_map[i].port != port) continue;
        if (mp_port_dead(port) || !mp_is_member(g_mp_map[i].pset, port)) {
            mp_release_locked(i);
            return -1;
        }
        return i;
    }
    return -1;
}

static mach_port_t mp_lookup_pset(mach_port_t port) {
    pthread_mutex_lock(&g_mp_mu);
    int i = mp_find_valid_locked(port);
    mach_port_t r = (i >= 0) ? g_mp_map[i].pset : MACH_PORT_NULL;
    pthread_mutex_unlock(&g_mp_mu);
    return r;
}

/* Drop the mapping for a fired one-shot. Bun registers getaddrinfo_async reply
 * ports EV_ONESHOT, so once the event is delivered the kernel has already
 * removed the filter and the mapping is dead weight. Reclaiming it here is what
 * keeps the table from filling up: without it every DNS lookup permanently
 * burned a slot (~5 per WebFetch), and once all MP_MAP_SIZE slots were gone
 * every later registration went through unwrapped, was rejected by 10.9 with
 * EV_ERROR, and the lookup hung forever. */
static void mp_release_by_pset(mach_port_t pset) {
    pthread_mutex_lock(&g_mp_mu);
    for (int i = 0; i < MP_MAP_SIZE; i++) {
        if (g_mp_map[i].pset == pset) { mp_release_locked(i); break; }
    }
    pthread_mutex_unlock(&g_mp_mu);
}

/* Given a receive-right port that Bun wants to register with
 * EVFILT_MACHPORT, ensure there's a portset wrapping it and return the
 * portset's name. Idempotent: repeated calls for the same port
 * return the same portset. */
static mach_port_t mp_get_or_create_pset(mach_port_t port, int no_drain) {
    if (port == MACH_PORT_NULL) return MACH_PORT_NULL;
    mach_port_t existing = mp_lookup_pset(port);
    if (existing != MACH_PORT_NULL) return existing;

    mach_port_t self = mach_task_self();
    mach_port_t pset = MACH_PORT_NULL;
    kern_return_t kr = mach_port_allocate(self, MACH_PORT_RIGHT_PORT_SET, &pset);
    if (kr != KERN_SUCCESS) return MACH_PORT_NULL;
    kr = mach_port_move_member(self, port, pset);
    if (kr != KERN_SUCCESS) {
        mach_port_mod_refs(self, pset, MACH_PORT_RIGHT_PORT_SET, -1);
        return MACH_PORT_NULL;
    }

    pthread_mutex_lock(&g_mp_mu);
    int slot = -1;
    for (int i = 0; i < MP_MAP_SIZE; i++) {
        /* Someone else may have installed it while we were creating; prefer
         * theirs. Hand the port back to their portset before dropping ours —
         * our move_member above pulled it out of theirs. */
        if (g_mp_map[i].port == port) {
            mach_port_t other = g_mp_map[i].pset;
            pthread_mutex_unlock(&g_mp_mu);
            mach_port_move_member(self, port, other);
            mach_port_mod_refs(self, pset, MACH_PORT_RIGHT_PORT_SET, -1);
            return other;
        }
        if (slot < 0 && g_mp_map[i].port == MACH_PORT_NULL) slot = i;
    }
    /* Table full: reclaim slots whose mapping has gone stale (port destroyed,
     * or its name recycled onto a port that is no longer a member). Normally
     * one-shot entries are released as they fire, so this only matters for
     * lookups that were cancelled before firing. */
    if (slot < 0) {
        for (int i = 0; i < MP_MAP_SIZE; i++) {
            if (mp_port_dead(g_mp_map[i].port) ||
                !mp_is_member(g_mp_map[i].pset, g_mp_map[i].port)) {
                tlog("MACHPORT-GC slot=%d port=%u", i, (unsigned)g_mp_map[i].port);
                mp_release_locked(i);
                slot = i;
                break;
            }
        }
    }
    if (slot < 0) { /* still full — fall back to an unwrapped registration */
        pthread_mutex_unlock(&g_mp_mu);
        tlog("MACHPORT-TABLE-FULL port=%u (registration will not be wrapped)",
             (unsigned)port);
        mach_port_move_member(self, port, MACH_PORT_NULL);
        mach_port_mod_refs(self, pset, MACH_PORT_RIGHT_PORT_SET, -1);
        return MACH_PORT_NULL;
    }
    g_mp_map[slot].port = port;
    g_mp_map[slot].pset = pset;
    g_mp_map[slot].no_drain = no_drain;
    pthread_mutex_unlock(&g_mp_mu);
    return pset;
}

/* The portset fires — we don't know which member port has a message
 * without receiving. A bare mach_msg(MACH_RCV_MSG, header_port=pset)
 * will dequeue from whichever member port has a message and set
 * msgh_local_port to that port. We discard the payload (Bun's wakeup
 * messages carry no body). */
/* Receive-and-discard any messages pending on a port/portset. Uses a
 * 64KB stack scratch; for anything larger we fall back to heap via
 * MACH_RCV_LARGE. Loops until the kernel reports the queue is empty. */
/* Receive-and-discard every message currently queued on a port or
 * portset. Uses a 64KB stack buffer; for anything larger (Bun's
 * wakeup messages aren't, but defensively handle it) MACH_RCV_LARGE
 * lets us grow to heap. Loops until the kernel reports empty. */
static void mp_drain_any(mach_port_t rcv_port) {
    uint8_t stack_buf[65536] __attribute__((aligned(16)));
    mach_msg_header_t *hdr = (mach_msg_header_t *)stack_buf;
    size_t cap = sizeof(stack_buf);
    void *heap = NULL;
    for (;;) {
        mach_msg_return_t kr = mach_msg(
            hdr,
            MACH_RCV_MSG | MACH_RCV_TIMEOUT | MACH_RCV_LARGE,
            0,
            (mach_msg_size_t)cap,
            rcv_port,
            0,
            MACH_PORT_NULL);
        if (kr == KERN_SUCCESS) {
            mach_msg_destroy(hdr);
            continue;
        }
        if (kr == MACH_RCV_TOO_LARGE) {
            size_t need = (size_t)hdr->msgh_size + sizeof(mach_msg_trailer_t) + 32;
            void *nh = heap ? realloc(heap, need) : malloc(need);
            if (!nh) break;
            heap = nh;
            hdr = (mach_msg_header_t *)heap;
            cap = need;
            continue;
        }
        break;  /* MACH_RCV_TIMED_OUT or other — done */
    }
    if (heap) free(heap);
}

/* Opt-in mach-port activity trace: set MAV_MACHPORT_LOG=/path to enable.
 * Kept as a callable (though currently uninstrumented) hook so a future
 * debug session can re-add log points without reintroducing the
 * forward-declaration churn. */
__attribute__((unused))
static FILE *machport_log(void) {
    static FILE *f = (FILE *)-1;
    if (f == (FILE *)-1) {
        const char *p = getenv("MAV_MACHPORT_LOG");
        f = (p && *p) ? fopen(p, "a") : NULL;
        if (f) setvbuf(f, NULL, _IOLBF, 0);
    }
    return f;
}
/* After kevent64 delivers EVFILT_MACHPORT, (a) drain the underlying
 * port queue — Bun's us_internal_accept_poll_event is a no-op on
 * kqueue and Bun normally relies on the kernel's
 * MACH_RCV_MSG|MACH_RCV_OVERWRITE side-effect to pull the message
 * out, which 10.9 doesn't implement — and (b) rewrite the ident back
 * from our wrapping portset to the caller-visible port. Without (a)
 * the port's 1-slot queue stays full and every subsequent
 * us_internal_async_wakeup send returns MACH_SEND_TIMED_OUT; Bun
 * interprets that as "already pending" so no new message is ever
 * sent, and the target thread's kevent64 parks forever. */
static void machport_drain_fired(struct kevent64_s *evs, int n) {
    for (int i = 0; i < n; i++) {
        if (evs[i].filter != EVFILT_MACHPORT) continue;
        if (evs[i].flags & EV_ERROR) continue;
        mach_port_t ident_port = (mach_port_t)evs[i].ident;
        if (ident_port == MACH_PORT_NULL) continue;
        mach_port_t original_port = MACH_PORT_NULL;
        int no_drain = 0;
        pthread_mutex_lock(&g_mp_mu);
        for (int j = 0; j < MP_MAP_SIZE; j++) {
            if (g_mp_map[j].pset == ident_port) {
                original_port = g_mp_map[j].port;
                no_drain = g_mp_map[j].no_drain;
                break;
            }
        }
        pthread_mutex_unlock(&g_mp_mu);
        /* no_drain ports (e.g. getaddrinfo_async reply ports registered
         * EV_ONESHOT with fflags=0): the caller does its own mach_msg
         * receive (getaddrinfo_async_handle_reply), so we must NOT consume
         * the message — only translate the portset ident back to the port
         * Bun registered, so its dispatcher matches the fire to its poll. */
        if (!no_drain) mp_drain_any(ident_port);
        if (original_port != MACH_PORT_NULL) {
            evs[i].ident = original_port;
            tlog("MACHPORT-FIRE pset=%u -> port=%u no_drain=%d",
                 (unsigned)ident_port, (unsigned)original_port, no_drain);
            /* no_drain entries are the bare EV_ONESHOT getaddrinfo_async reply
             * ports: the kernel dropped the filter when it fired, so the
             * mapping is spent. Release it now — the message stays queued on
             * the port for getaddrinfo_async_handle_reply, and the slot goes
             * back to the table instead of leaking for the process's lifetime.
             * The `modern` wakeup-async ports are long-lived and re-fire, so
             * their mappings must survive. */
            if (no_drain) mp_release_by_pset(ident_port);
        }
    }
}

int kevent64_wrapper(int kq, const struct kevent64_s *changelist, int nchanges,
                     struct kevent64_s *eventlist, int nevents,
                     unsigned int flags, const struct timespec *timeout) {
    static int (*real_kevent64)(int, const struct kevent64_s *, int,
                                struct kevent64_s *, int, unsigned int,
                                const struct timespec *) = NULL;
    if (!real_kevent64) real_kevent64 = dlsym(RTLD_NEXT, "kevent64");
    if (!g_trace_ready) trace_init();
    if (g_trace && nchanges > 0) {
        for (int _i = 0; _i < nchanges; _i++)
            tlog("CHG kq=%d ident=%llu filter=%d flags=0x%x fflags=0x%x data=%lld",
                 kq, (unsigned long long)changelist[_i].ident, changelist[_i].filter,
                 changelist[_i].flags, changelist[_i].fflags, (long long)changelist[_i].data);
    }

    /* Translate Bun's EVFILT_MACHPORT registrations to 10.9's vintage
     * requirements.
     *
     * Modern macOS lets you register EVFILT_MACHPORT directly on a
     * receive-right port, with `fflags = MACH_RCV_MSG | MACH_RCV_OVERWRITE`
     * and `ext[0]` pointing at a user-supplied receive buffer that the
     * kernel fills in on delivery. 10.9 supports neither the direct-
     * on-receive-port registration nor the ext[] receive buffer: it
     * returns `EV_ERROR, data=EOPNOTSUPP` for any EV_ADD on a port that
     * isn't a *portset*. The net effect in Bun is that the HTTP client
     * thread's wakeup async never actually installs a filter — the
     * first request is processed by drainEvents() in the pre-tick
     * path, but the second request after the idle tries to wake a
     * thread whose kevent64 has nothing that will ever fire.
     *
     * Fix: at EV_ADD time, create a portset, move the receive port
     * into it, and substitute the portset's name as the kevent's
     * ident. Also strip fflags/ext[] since 10.9 ignores (or rejects)
     * those. Remember the port→portset mapping so we can (a) drain
     * the right port when the portset fires, and (b) clean up the
     * portset on EV_DELETE. */
    /* EVFILT_MACHPORT translation: wrap ports that use the 10.10+
     * `fflags = MACH_RCV_MSG | MACH_RCV_OVERWRITE` + `ext[]` receive-
     * buffer variant in a portset. Only these are rejected by 10.9's
     * kernel (EV_ERROR + EOPNOTSUPP); registrations with fflags==0
     * work natively (CoreFoundation's CFRunLoop, libdispatch mach
     * sources, etc.) and must be passed through unchanged — wrapping
     * them reroutes their receive semantics and breaks the owning
     * subsystem (e.g. CFRunLoop stops pumping, killing the main-
     * thread render loop). */
    struct kevent64_s mp_rewritten[nchanges > 0 ? nchanges : 1];
    int mp_rewrote = 0;
    for (int i = 0; i < nchanges; i++) {
        if (changelist[i].filter != EVFILT_MACHPORT) continue;
        if (!(changelist[i].flags & EV_ADD)) continue;
        /* Two kinds of EVFILT_MACHPORT registration need wrapping on 10.9:
         *
         *  (1) Modern receive-and-overwrite: fflags has MACH_RCV_MSG (0x02)
         *      or MACH_RCV_OVERWRITE (0x1000). Bun's loop wakeup async. The
         *      kernel is expected to dequeue into ext[]; 10.9 doesn't, so we
         *      wrap in a portset AND drain (Bun never receives it itself —
         *      it's a pure wakeup signal).
         *
         *  (2) Bare one-shot: fflags==0 with EV_ONESHOT. This is libinfo's
         *      getaddrinfo_async reply port — Bun registers it to be told
         *      "a message arrived", then calls getaddrinfo_async_handle_reply
         *      to receive it. On 10.9 a bare EVFILT_MACHPORT on Bun's kqueue
         *      never fires for these dynamically-created reply ports, so the
         *      DNS callback never runs and the lookup hangs forever. Wrap it
         *      in a portset so 10.9 reliably fires — but mark it no_drain so
         *      we leave the message for handle_reply to receive.
         *
         * Other bare (fflags==0, non-one-shot) registrations are left native:
         * those are CFRunLoop / libdispatch mach sources that receive on the
         * port themselves and must not be re-homed into our portset. */
        int modern = (changelist[i].fflags & (0x00000002u | 0x00001000u)) != 0;
        int bare_oneshot = (changelist[i].fflags == 0) &&
                           (changelist[i].flags & EV_ONESHOT);
        if (!modern && !bare_oneshot) continue;
        mach_port_t port = (mach_port_t)changelist[i].ident;
        mach_port_t pset = mp_get_or_create_pset(port, /*no_drain=*/!modern);
        if (pset == MACH_PORT_NULL) continue;
        if (!mp_rewrote) {
            for (int j = 0; j < nchanges; j++) mp_rewritten[j] = changelist[j];
            mp_rewrote = 1;
        }
        mp_rewritten[i].ident = pset;
        if (modern) {
            mp_rewritten[i].fflags = 0;
            mp_rewritten[i].ext[0] = 0;
            mp_rewritten[i].ext[1] = 0;
        }
        /* bare_oneshot: keep fflags(0)/flags(EV_ADD|EV_ONESHOT) as-is, just
         * swap the ident to the wrapping portset. */
        tlog("MACHPORT-WRAP port=%u pset=%u modern=%d oneshot=%d",
             (unsigned)port, (unsigned)pset, modern, bare_oneshot ? 1 : 0);
    }
    if (mp_rewrote) changelist = mp_rewritten;
    (void)mp_lookup_pset;

    /* Strip FLAG_ERROR_EVENTS and force zero timeout when it's set —
     * the modern kernel returns immediately after submitting changes in
     * that mode, regardless of the passed timeout. 10.9 doesn't know the
     * flag; if the caller passes NULL timeout it would block forever
     * waiting for events. (Bun always passes {0,0}, but keep this
     * defensive for other callers.)
     *
     * NOTE: we deliberately do NOT intercept KEVENT_FLAG_IMMEDIATE here.
     * In theory it should behave the same way (return immediately), but
     * empirically Bun's main loop combines IMMEDIATE with had_wakeups and
     * relies on 10.9's "flag ignored, respect caller timeout" behavior as
     * natural pacing. Forcing zero-timeout there uncorks an upstream JS
     * wakeup loop that runs main-thread-hot (366% CPU observed). Leave
     * IMMEDIATE to fall through untouched. */
    unsigned int kflags = flags & ~KEVENT_FLAG_ERROR_EVENTS;
    static const struct timespec zero_ts = {0, 0};
    const struct timespec *real_timeout = timeout;
    if (flags & KEVENT_FLAG_ERROR_EVENTS)
        real_timeout = &zero_ts;

    /* Case 1: add-only call with FLAG_ERROR_EVENTS semantics. The caller (e.g.
     * Bun's uSockets / FilePoll registration) wants to register filters and
     * receive only real EV_ERROR events; any fires the new filters produce
     * stay with the kernel for a later wait. 10.9 doesn't know the flag and
     * hands ready events back on the register call — consuming EV_ONESHOT
     * and EV_DISPATCH ones, which never re-fire (Bun's stdin is EV_DISPATCH).
     *
     * EV_RECEIPT gives the modern semantics on 10.9: one EV_ERROR receipt per
     * change, and with exactly nchanges slots the kernel has no room left to
     * report, and so consume, any ready event. They are delivered on the next
     * wait like any other.
     *
     * This replaces stashing those events here for replay. A stash outlives
     * the fd it describes: uSockets frees the us_poll_t with the fd, the
     * number is reused by the next socket()/open()/pipe(), and replaying the
     * stale event hands the freed poll to us_internal_dispatch_ready_poll —
     * Claude Code's intermittent launch crash, a call through NULL there.
     * The kernel, by contrast, drops a filter's pending fire when its fd is
     * closed. */
    if ((flags & KEVENT_FLAG_ERROR_EVENTS) && nchanges > 0) {
        struct kevent64_s with_receipt[nchanges];
        struct kevent64_s receipts[nchanges];
        for (int i = 0; i < nchanges; i++) {
            with_receipt[i] = changelist[i];
            with_receipt[i].flags |= EV_RECEIPT;
        }
        int rc = real_kevent64(kq, with_receipt, nchanges, receipts, nchanges, kflags, real_timeout);
        if (rc < 0) return rc;
        /* Successful receipts are not errors: uSockets treats any returned
         * event as a failed registration and frees the poll. */
        int kept = 0;
        for (int i = 0; i < rc && kept < nevents; i++) {
            if ((receipts[i].flags & EV_ERROR) && receipts[i].data != 0)
                eventlist[kept++] = receipts[i];
        }
        return kept;
    }

    /* Case 2: a wait (with or without changes), passed straight through. */
    int rc2 = real_kevent64(kq, changelist, nchanges, eventlist, nevents,
                            kflags, real_timeout);
    if (dbg_on() && nchanges == 0 && nevents > 0) {
        DBG("kevent64_wait kq=%d nevs=%d fl=0x%x to=%p rc=%d",
            kq, nevents, kflags, (void*)real_timeout, rc2);
        for (int i = 0; i < rc2 && i < 3; i++)
            DBG("  ev[%d] fd=%llu filter=%d flags=0x%x fflags=0x%x data=%lld udata=0x%llx",
                i, eventlist[i].ident, eventlist[i].filter, eventlist[i].flags,
                eventlist[i].fflags, (long long)eventlist[i].data,
                (unsigned long long)eventlist[i].udata);
    }
    if (rc2 < 0) return rc2;
    machport_drain_fired(eventlist, rc2);
    return rc2;
}

/* DIAGNOSTIC (MAV_KQ_TRACE): mark when the new-connection path touches sockets. */
int mav_socket(int domain, int type, int protocol) __asm("_socket");
int mav_socket(int domain, int type, int protocol) {
    static int (*real)(int,int,int) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "socket");
    int fd = real(domain, type, protocol);
    if (g_trace) { if (!g_trace_ready) trace_init(); tlog("SOCKET dom=%d type=%d -> fd=%d", domain, type, fd); }
    return fd;
}
int mav_connect(int fd, const struct sockaddr *addr, socklen_t len) __asm("_connect");
int mav_connect(int fd, const struct sockaddr *addr, socklen_t len) {
    static int (*real)(int,const struct sockaddr*,socklen_t) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "connect");
    if (g_trace) { if (!g_trace_ready) trace_init();
        int fam = addr?addr->sa_family:-1, port=0;
        if (addr && fam==2)  port = ntohs(((const struct sockaddr_in *)addr)->sin_port);
        if (addr && fam==30) port = ntohs(((const struct sockaddr_in6 *)addr)->sin6_port);
        tlog("CONNECT fd=%d fam=%d port=%d", fd, fam, port);
    }
    return real(fd, addr, len);
}
