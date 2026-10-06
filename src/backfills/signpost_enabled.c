/*
 * signpost_enabled.c -- MavericksLegacySupport libSystem shim.
 * Split verbatim from the former modern_api_polyfills.c; the shared DBG
 * helper and common includes live in mav_shim_debug.h.
 */
#include "mav_shim_debug.h"

/* ── signposts: tracing no-ops ────────────────────────────────────────── */
int os_signpost_enabled(void *log) { (void)log; DBG("signpost_enabled"); return 0; }

