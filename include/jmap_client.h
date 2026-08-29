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

/* --- Bring your own HTTP -------------------------------------------- */

typedef enum {
  JMAP_HTTP_GET  = 0,
  JMAP_HTTP_POST = 1
} jmap_http_method;

typedef enum {
  JMAP_TRANSPORT_OK      = 0,
  JMAP_TRANSPORT_NETWORK = 1,
  JMAP_TRANSPORT_TLS     = 2,
  JMAP_TRANSPORT_TIMEOUT = 3
} jmap_transport_code;

/* Perform one HTTP exchange. url, body and authorization are
 * library-owned borrows: never NULL (a GET body is the empty string,
 * not NULL) and valid only for the duration of this call — copy
 * anything the callback needs to keep past return. On
 * JMAP_TRANSPORT_OK the callback sets *out_http_status and hands back
 * malloc'd *out_content_type and *out_body buffers — the library
 * copies both and frees them with the C library's free(). On any
 * other return the out-parameters are ignored. The callback must not
 * unwind; userdata is threaded back unchanged and never dereferenced
 * by the library. Allocate *out_content_type and *out_body with the
 * same C runtime this library itself links: passing a buffer across
 * mismatched CRTs (e.g. two different Windows CRTs, or a debug and a
 * release CRT) is undefined once the library calls free() on it. */
typedef jmap_transport_code (*jmap_send_fn)(void *userdata,
                                            jmap_http_method method,
                                            const char *url,
                                            const char *body,
                                            const char *authorization,
                                            int *out_http_status,
                                            char **out_content_type,
                                            char **out_body);

/* Fires exactly once, when the last reference to the transport drops
 * (jmap_transport_free and/or jmap_client_free, whichever is last). */
typedef void (*jmap_close_fn)(void *userdata);

/* close may be NULL when there is nothing to release. One transport
 * backs at most one client: a second attach is JMAP_E_MISUSE. */
jmap_status jmap_transport_new(jmap_send_fn send,
                               jmap_close_fn close,
                               void *userdata,
                               jmap_transport **out);

/* Drops the caller's reference. If a client holds the other reference
 * the transport lives until jmap_client_free. NULL is a no-op. */
void jmap_transport_free(jmap_transport *transport);

/* --- Session and accounts ------------------------------------------- */
/* These fetch and cache the JMAP session on first use (which is why
 * they take a non-const client): expect transport/protocol statuses on
 * that first call. Account ids are returned in ascending strcmp order,
 * stable until jmap_client_free. */

/* The RFC 8621 mail primary account (with the library's documented
 * fallback to the lowest-sorting mail-capable account when the
 * designated primary lacks the capability). JMAP_E_SESSION when no
 * account advertises mail. The borrow is owned by the client handle. */
jmap_status jmap_client_primary_account(jmap_client *client,
                                        const char **out);

jmap_status jmap_client_account_count(jmap_client *client, size_t *out);

/* Pure read: NULL when out of range or when no fetch has succeeded yet
 * (call jmap_client_account_count first). */
const char *jmap_client_account_at(const jmap_client *client, size_t i);

/* --- Wire debugging -------------------------------------------------- */

typedef enum {
  JMAP_WIRE_SEND    = 0,
  JMAP_WIRE_RECEIVE = 1
} jmap_wire_direction;

/* Fires once per direction per HTTP exchange the client attempts —
 * up to two calls per exchange, never more. A send fire is NOT
 * guaranteed a matching receive fire: the request is rendered (and
 * the send fire raised) before the request-size check and before the
 * transport call, so an oversized request, an unresolved session
 * URL, or a transport failure can leave a send with no corresponding
 * receive.
 *
 * bytes is never NULL, even when len is 0 — e.g. the GET request that
 * fetches the session has an empty body, so that is every client's
 * very first fire — so memcpy(dst, bytes, len) is always well
 * defined. bytes is length-delimited, NOT NUL-terminated: do not
 * treat it as a C string. It is borrowed for the duration of the
 * call only — copy it if you keep it. The callback must not unwind.
 * As with jmap_send_fn, it fires while an exchange is in flight:
 * freeing the client it was invoked from before returning is a
 * use-after-free the caller must avoid, not a case the library
 * guards against. */
typedef void (*jmap_debug_fn)(void *userdata,
                              jmap_wire_direction direction,
                              const uint8_t *bytes,
                              size_t len);

/* fn == NULL detaches. userdata is threaded back unchanged. */
jmap_status jmap_set_debug_callback(jmap_client *client,
                                    jmap_debug_fn fn,
                                    void *userdata);

#ifdef __cplusplus
}
#endif
#endif /* JMAP_CLIENT_H */
