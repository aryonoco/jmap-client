/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
/*
 * jmap_client — C API for the jmap-client JMAP (RFC 8620/8621) library.
 *
 * Contract summary (details on each declaration):
 *   - Call jmap_init() once per process before anything else; only
 *     jmap_strerror() and jmap_version() are callable before it.
 *   - Every fallible function returns a jmap_status; outputs travel
 *     through out-parameters. Rich diagnostics: jmap_errmsg(client).
 *   - The library owns everything its read accessors return: a
 *     const char* or view is a borrow, valid until the handle that
 *     produced it is freed (jmap_errmsg's borrow is also invalidated
 *     by the next fallible call on the same client). Never free a
 *     borrow. Objects are released only via their paired jmap_*_free.
 *   - A handle is confined to one thread at a time; hand a handle to
 *     another thread by ceasing to use it on the old one.
 *   - This header is the ABI: symbols are appended, ordinals never
 *     reused, nothing removed after v1 (additive-only until a SemVer
 *     policy document supersedes this note).
 */
#ifndef JMAP_CLIENT_H
#define JMAP_CLIENT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define JMAP_CLIENT_VERSION_MAJOR 0
#define JMAP_CLIENT_VERSION_MINOR 1
#define JMAP_CLIENT_VERSION_PATCH 0

typedef enum {
  JMAP_OK           = 0,
  JMAP_E_VALIDATION = 1, /* client-supplied input was invalid */
  JMAP_E_TRANSPORT  = 2, /* network / TLS / timeout / HTTP status */
  JMAP_E_REQUEST    = 3, /* whole request rejected (RFC 7807) */
  JMAP_E_SESSION    = 4, /* expected session capability absent */
  JMAP_E_MISUSE     = 5, /* caller bug: NULL argument, wrong handle */
  JMAP_E_PROTOCOL   = 6, /* malformed or non-conforming response */
  JMAP_E_METHOD     = 7, /* method-level error (one-shot path) */
  JMAP_E_SET        = 8  /* /set error (one-shot path) */
  /* additive growth only — existing ordinals never change */
} jmap_status;

/* Once per process, before any other call except jmap_strerror and
 * jmap_version. Initialises the language runtime (the library is a
 * --noMain shared object). Idempotent. */
jmap_status jmap_init(void);

/* Optional teardown at process exit. Not thread-safe against live
 * handles: free every handle first. */
void jmap_cleanup(void);

/* Static description of a status code. Never NULL, never freed,
 * callable before jmap_init. */
const char *jmap_strerror(jmap_status code);

/* Static library version string, "MAJOR.MINOR.PATCH". Callable before
 * jmap_init. */
const char *jmap_version(void);

/* Opaque handles. Struct layouts are never exposed. */
typedef struct jmap_client jmap_client;
typedef struct jmap_transport jmap_transport;

/* Connect parameters, Basic authentication. transport == NULL selects
 * the built-in HTTP transport; a non-NULL transport (jmap_transport_new)
 * attaches caller-supplied HTTP. No network IO happens here — the JMAP
 * session is fetched on first use, so reachability errors surface on
 * the first operation, not here. On failure *out is untouched and the
 * returned status is the diagnosis (no handle exists yet to query). */
jmap_status jmap_client_new(const char *session_url,
                            const char *username,
                            const char *password,
                            jmap_transport *transport,
                            jmap_client **out);

/* Releases the client, closing its transport. NULL is a no-op. */
void jmap_client_free(jmap_client *client);

/* The most recent error on THIS handle (sqlite3_errmsg semantics): the
 * borrow is owned by the handle, valid until the next fallible call on
 * the same handle or jmap_client_free, whichever comes first. Returns
 * "no error" when the last call succeeded. */
const char *jmap_errmsg(const jmap_client *client);

#ifdef __cplusplus
}
#endif
#endif /* JMAP_CLIENT_H */
