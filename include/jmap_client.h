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
 *     produced it is freed (jmap_errmsg's, jmap_errtype's, and
 *     jmap_get_email_state's borrows are also invalidated by the next
 *     fallible call on the same client). Never free a borrow. Objects
 *     are released only via their paired jmap_*_free.
 *   - A handle is confined to one thread at a time; hand a handle to
 *     another thread by ceasing to use it on the old one.
 *   - This header is the ABI. The library is pre-1.0 (see the version
 *     macros below): the C ABI may still change, and no compatibility
 *     promise is made to consumers yet. Ordinals are not renumbered
 *     casually all the same — a render of this file is checked in as
 *     a snapshot and compared in CI, so a change to a type, an
 *     ordinal or a macro here is a deliberate act rather than an
 *     accidental one.
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
  /* Pre-1.0: these ordinals are not frozen. CI compares this file
   * against a committed snapshot, so a change to them is deliberate
   * rather than accidental. */
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

/* The wire "type" string (RFC 8620 section 3.6.2, e.g.
 * "cannotCalculateChanges") of the last JMAP method-level error on
 * THIS handle -- the machine-readable counterpart to jmap_errmsg's
 * prose, on the sqlite3_errmsg/sqlite3_extended_errcode split (SQLite:
 * "the same except that it always returns the extended result code")
 * rather than CURLOPT_ERRORBUFFER's human-text-only design. The
 * substrate carries this off the wire losslessly, so a vendor-specific
 * type reaches C intact, exactly like jmap_set_result_failure_type_at.
 *
 * NULL when the last call did NOT fail with a method-level error --
 * no client, no error, or a failure of any other status
 * (JMAP_E_VALIDATION, JMAP_E_SESSION, ...). When non-NULL the string
 * is never empty, so "not a method error" and "a method error with an
 * empty type" can never be confused. Same borrow lifetime as
 * jmap_errmsg: owned by the handle, invalidated by the next fallible
 * call on it or by jmap_client_free, whichever comes first. */
const char *jmap_errtype(const jmap_client *client);

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

/* --- Mailboxes -------------------------------------------------------- */

typedef struct jmap_mailboxes jmap_mailboxes;
typedef struct jmap_mailbox jmap_mailbox; /* a borrow, never freed */

/* Pre-1.0: these ordinals are not frozen, but CI snapshots this file,
 * so a change to them is deliberate. NONE = the mailbox has no role;
 * UNKNOWN = a role this library version does not recognise (read the
 * raw wire string via jmap_mailbox_role_identifier). */
typedef enum {
  JMAP_ROLE_NONE      = 0,
  JMAP_ROLE_INBOX     = 1,
  JMAP_ROLE_DRAFTS    = 2,
  JMAP_ROLE_SENT      = 3,
  JMAP_ROLE_TRASH     = 4,
  JMAP_ROLE_JUNK      = 5,
  JMAP_ROLE_ARCHIVE   = 6,
  JMAP_ROLE_IMPORTANT = 7,
  JMAP_ROLE_ALL       = 8,
  JMAP_ROLE_FLAGGED   = 9,
  JMAP_ROLE_UNKNOWN   = 10
} jmap_mailbox_role;

typedef enum {
  JMAP_RIGHT_READ_ITEMS   = 0,
  JMAP_RIGHT_ADD_ITEMS    = 1,
  JMAP_RIGHT_REMOVE_ITEMS = 2,
  JMAP_RIGHT_SET_SEEN     = 3,
  JMAP_RIGHT_SET_KEYWORDS = 4,
  JMAP_RIGHT_CREATE_CHILD = 5,
  JMAP_RIGHT_RENAME       = 6,
  JMAP_RIGHT_DELETE       = 7,
  JMAP_RIGHT_SUBMIT       = 8
} jmap_mailbox_right;

jmap_status jmap_get_mailboxes(jmap_client *client,
                               const char *account_id,
                               jmap_mailboxes **out);
void jmap_mailboxes_free(jmap_mailboxes *mailboxes);

size_t jmap_mailboxes_count(const jmap_mailboxes *mailboxes);
/* NULL out of range. The borrow lives until jmap_mailboxes_free. */
const jmap_mailbox *jmap_mailboxes_at(const jmap_mailboxes *mailboxes,
                                      size_t i);

const char *jmap_mailbox_id(const jmap_mailbox *mb);
const char *jmap_mailbox_name(const jmap_mailbox *mb);
jmap_mailbox_role jmap_mailbox_role_get(const jmap_mailbox *mb);
/* The raw wire role string; "" when the mailbox has no role. */
const char *jmap_mailbox_role_identifier(const jmap_mailbox *mb);
/* NULL when the mailbox is top-level. */
const char *jmap_mailbox_parent_id(const jmap_mailbox *mb);
int64_t jmap_mailbox_total_emails(const jmap_mailbox *mb);
int64_t jmap_mailbox_unread_emails(const jmap_mailbox *mb);
/* 1 or 0. */
int jmap_mailbox_is_subscribed(const jmap_mailbox *mb);
int jmap_mailbox_has_right(const jmap_mailbox *mb, jmap_mailbox_right r);

/* --- Emails ----------------------------------------------------------- */

typedef struct jmap_emails jmap_emails;
typedef struct jmap_email jmap_email; /* a borrow, never freed */

/* Fetches the named emails with their text bodies. ids is an array of
 * n id strings (as returned by other calls). */
jmap_status jmap_get_emails(jmap_client *client,
                            const char *account_id,
                            const char *const *ids,
                            size_t n,
                            jmap_emails **out);
void jmap_emails_free(jmap_emails *emails);

size_t jmap_emails_count(const jmap_emails *emails);
/* NULL out of range. The borrow lives until jmap_emails_free. */
const jmap_email *jmap_emails_at(const jmap_emails *emails, size_t i);
size_t jmap_emails_notfound_count(const jmap_emails *emails);
/* NULL out of range. The borrow lives until jmap_emails_free. */
const char *jmap_emails_notfound_at(const jmap_emails *emails, size_t i);

/* Getters return NULL when the server omitted the field, except
 * jmap_email_preview: RFC 8621 §4.1.4 makes preview non-optional
 * (server-set, defaulting to ""), so it is never NULL for a live
 * handle. */
const char *jmap_email_id(const jmap_email *e);
const char *jmap_email_thread_id(const jmap_email *e);
const char *jmap_email_subject(const jmap_email *e);
/* First From address (the common display case). A present-but-empty
 * "from": [] server response is indistinguishable here from an absent
 * from: both jmap_email_from_email and jmap_email_from_name answer
 * NULL either way. */
const char *jmap_email_from_email(const jmap_email *e);
const char *jmap_email_from_name(const jmap_email *e);
const char *jmap_email_preview(const jmap_email *e);
/* RFC 3339 UTC date string. */
const char *jmap_email_received_at(const jmap_email *e);
/* The decoded text/plain body, when one was fetched. */
const char *jmap_email_text_body(const jmap_email *e);
int jmap_email_has_attachment(const jmap_email *e);

/* --- Email query -------------------------------------------------------- */

typedef struct jmap_query jmap_query;

typedef enum {
  JMAP_Q_IN_MAILBOX = 0, /* string: mailbox id */
  JMAP_Q_TEXT       = 1, /* string: full-text needle */
  JMAP_Q_LIMIT      = 2, /* u32: max results, 0 = server default */
  JMAP_Q_READ_STATE = 3, /* u32: a jmap_read_state ordinal */
  JMAP_Q_SORT       = 4  /* u32: a jmap_sort ordinal */
  /* Pre-1.0: these members are not frozen, but CI snapshots this
   * file, so a change to them is deliberate. */
} jmap_query_opt;

typedef enum {
  JMAP_READ_ANY    = 0,
  JMAP_READ_UNREAD = 1,
  JMAP_READ_READ   = 2
} jmap_read_state;

typedef enum {
  JMAP_SORT_RECEIVED_AT_DESC = 0,
  JMAP_SORT_RECEIVED_AT_ASC  = 1
} jmap_sort;

jmap_status jmap_query_new(jmap_query **out);
/* NULL is a no-op. Freeing after jmap_query_emails has consumed the
 * query is correct: the call copies what it needs. */
void jmap_query_free(jmap_query *query);

/* Typed option setters (the sqlite3_bind_* discipline): each option's
 * type is documented above; using the wrong-type setter for an
 * option, a NULL string value, or an out-of-range ordinal is
 * JMAP_E_MISUSE — the query handle carries no error slot of its own,
 * so the returned status is the whole diagnosis for which setter
 * failed. Values are parsed and validated HERE, not when the query
 * runs: a value of the right type that is not a legal JMAP value (a
 * malformed mailbox id) is JMAP_E_VALIDATION and leaves the spec
 * unchanged. Calling a setter twice for the SAME option replaces its
 * earlier value outright. JMAP_Q_IN_MAILBOX, JMAP_Q_TEXT and
 * JMAP_Q_READ_STATE each set one property on a single accumulated
 * filter condition (all three narrow the same query, in conjunction);
 * JMAP_Q_LIMIT and JMAP_Q_SORT are independent slots outside that
 * condition. */
jmap_status jmap_query_set_str(jmap_query *query, jmap_query_opt opt,
                               const char *value);
jmap_status jmap_query_set_u32(jmap_query *query, jmap_query_opt opt,
                               uint32_t value);

/* Runs Email/query (RFC 8621 section 4.4) then fetches the matching
 * records' text bodies via Email/get (RFC 8621 section 4.2) in one
 * round trip. query may be NULL: no filter, no sort, server-default
 * paging — a legal, unfiltered request rather than a special case. */
jmap_status jmap_query_emails(jmap_client *client,
                              const char *account_id,
                              const jmap_query *query,
                              jmap_emails **out);

/* --- Threads and identities -------------------------------------------- */

typedef struct jmap_threads jmap_threads;
typedef struct jmap_thread jmap_thread; /* a borrow, never freed */
typedef struct jmap_identities jmap_identities;
typedef struct jmap_identity jmap_identity; /* a borrow, never freed */

jmap_status jmap_get_threads(jmap_client *client, const char *account_id,
                             const char *const *ids, size_t n,
                             jmap_threads **out);
void jmap_threads_free(jmap_threads *threads);
size_t jmap_threads_count(const jmap_threads *threads);
/* NULL out of range. The borrow lives until jmap_threads_free. */
const jmap_thread *jmap_threads_at(const jmap_threads *threads, size_t i);
const char *jmap_thread_id(const jmap_thread *th);
size_t jmap_thread_email_count(const jmap_thread *th);
/* NULL out of range. th is itself a borrow into the threads handle
 * (never freed independently, per the typedef above), and so is this
 * return value: it lives until jmap_threads_free, not until any
 * per-thread lifetime that does not exist. */
const char *jmap_thread_email_at(const jmap_thread *th, size_t i);

jmap_status jmap_get_identities(jmap_client *client,
                                const char *account_id,
                                jmap_identities **out);
void jmap_identities_free(jmap_identities *identities);
size_t jmap_identities_count(const jmap_identities *identities);
/* NULL out of range. The borrow lives until jmap_identities_free. */
const jmap_identity *jmap_identities_at(const jmap_identities *identities,
                                        size_t i);
const char *jmap_identity_id(const jmap_identity *ident);
const char *jmap_identity_name(const jmap_identity *ident);
const char *jmap_identity_email(const jmap_identity *ident);

/* --- Email writes ----------------------------------------------------- */

typedef struct jmap_set_result jmap_set_result;

/* All four take an array of n email ids. Per-id refusals are DATA on
 * the result object; the returned status reports whole-call failure
 * only. Empty or duplicate ids reject with JMAP_E_VALIDATION before
 * any network traffic on the update rail (mark_read/mark_unread/
 * move); destroy accepts both an empty array (legal wire, destroys
 * nothing) and duplicate ids (forwarded to the server as given, which
 * answers each occurrence independently per RFC 8620 section 5.3 —
 * destroy has no client-side seal to reject a repeat).
 *
 * The updated/destroyed/failure lists on the returned jmap_set_result
 * reflect server table order, not the order ids were submitted in,
 * and that order is not guaranteed stable across calls. A caller
 * correlating results against its own submitted array MUST match by
 * id, never by index. */
jmap_status jmap_mark_read(jmap_client *client, const char *account_id,
                           const char *const *ids, size_t n,
                           jmap_set_result **out);
jmap_status jmap_mark_unread(jmap_client *client, const char *account_id,
                             const char *const *ids, size_t n,
                             jmap_set_result **out);
/* A full mailbox-membership replace: afterwards the emails are in
 * mailbox_id and nowhere else. */
jmap_status jmap_move_emails(jmap_client *client, const char *account_id,
                             const char *const *ids, size_t n,
                             const char *mailbox_id,
                             jmap_set_result **out);
jmap_status jmap_destroy_emails(jmap_client *client, const char *account_id,
                                const char *const *ids, size_t n,
                                jmap_set_result **out);
void jmap_set_result_free(jmap_set_result *result);

size_t jmap_set_result_updated_count(const jmap_set_result *r);
/* NULL out of range. The borrow lives until jmap_set_result_free. */
const char *jmap_set_result_updated_at(const jmap_set_result *r, size_t i);
size_t jmap_set_result_destroyed_count(const jmap_set_result *r);
/* NULL out of range. The borrow lives until jmap_set_result_free. */
const char *jmap_set_result_destroyed_at(const jmap_set_result *r, size_t i);
size_t jmap_set_result_failure_count(const jmap_set_result *r);
/* NULL out of range. The borrow lives until jmap_set_result_free. */
const char *jmap_set_result_failure_id_at(const jmap_set_result *r, size_t i);
/* NULL out of range. The borrow lives until jmap_set_result_free. The
 * wire SetError type, e.g. "notFound", "forbidden". */
const char *jmap_set_result_failure_type_at(const jmap_set_result *r,
                                            size_t i);

/* --- Vacation response ------------------------------------------------ */

typedef struct jmap_vacation jmap_vacation;
typedef struct jmap_vacation_update jmap_vacation_update;

typedef enum {
  JMAP_VACATION_DISABLED = 0,
  JMAP_VACATION_ENABLED  = 1
} jmap_vacation_state;

/* The account's vacation singleton. RFC 8621 section 8.1 requires the
 * server to return exactly one record; any other count answers
 * JMAP_E_PROTOCOL rather than guessing which record to expose. */
jmap_status jmap_get_vacation(jmap_client *client, const char *account_id,
                              jmap_vacation **out);
void jmap_vacation_free(jmap_vacation *vacation);
/* 1 or 0 — the same two values, in the same order, as
 * JMAP_VACATION_DISABLED and JMAP_VACATION_ENABLED, so what this
 * returns can be handed straight to jmap_vacation_update_set_enabled
 * on the write side. */
int jmap_vacation_is_enabled(const jmap_vacation *v);
/* NULL when unset. */
const char *jmap_vacation_subject(const jmap_vacation *v);
const char *jmap_vacation_text_body(const jmap_vacation *v);

/* Assembling an update (the same discipline the query options use:
 * one setter per property, values taken at the setter). A property no
 * setter named is LEFT UNTOUCHED by the update; a setter called with
 * NULL CLEARS that property to JSON null, which RFC 8621 section 8
 * permits for subject and textBody. Those are different requests, and
 * only the setter surface can tell them apart. Calling a setter twice
 * replaces the earlier value.
 *
 * Each setter answers JMAP_OK or JMAP_E_MISUSE (NULL handle,
 * out-of-range jmap_vacation_state ordinal, or a call before
 * jmap_init); a string value is never itself invalid, so no validation
 * status arises here. The update carries no error slot of its own, so
 * the returned status is the whole diagnosis.
 *
 * fromDate, toDate and htmlBody are NOT projected by this version. A
 * JMAP patch leaves an omitted property untouched, so enabling a
 * response through this surface leaves whatever window the singleton
 * already holds — possibly one another client wrote — exactly as it
 * was. RFC 8621 section 8 ties "effective immediately"/"effective
 * indefinitely" to a null fromDate/toDate ON THE RECORD, not to a
 * property a patch says nothing about, so the response is immediate
 * and indefinite only when the record's own fromDate and toDate are
 * already null. A later version may add setters for them. */
jmap_status jmap_vacation_update_new(jmap_vacation_update **out);
jmap_status jmap_vacation_update_set_enabled(jmap_vacation_update *update,
                                             jmap_vacation_state state);
jmap_status jmap_vacation_update_set_subject(jmap_vacation_update *update,
                                             const char *subject);
jmap_status jmap_vacation_update_set_text_body(jmap_vacation_update *update,
                                               const char *text_body);
/* NULL is a no-op. Freeing after jmap_set_vacation has consumed the
 * update is correct: the call copies what it needs. */
void jmap_vacation_update_free(jmap_vacation_update *update);

/* Updates the account's vacation singleton with the assembled patch.
 * update must not be NULL and must have had at least one setter called
 * on it: an empty patch is JMAP_E_VALIDATION and nothing is sent.
 *
 * JMAP_OK means the CALL completed, not that the server accepted the
 * change. A refusal is per-id data per RFC 8620 section 5.3: the
 * ordinary refused update is JMAP_OK with
 * jmap_set_result_updated_count() == 0 and
 * jmap_set_result_failure_count() == 1, the reason readable through
 * jmap_set_result_failure_type_at(). Read the counts before indexing
 * either list; neither list is guaranteed non-empty by the status.
 * jmap_set_result_destroyed_count() is structurally 0 for a vacation
 * result: this update submits no create or destroy rows, so those
 * rails have nothing to carry back. */
jmap_status jmap_set_vacation(jmap_client *client,
                              const char *account_id,
                              const jmap_vacation_update *update,
                              jmap_set_result **out);

/* --- Incremental sync ------------------------------------------------- */

typedef struct jmap_sync jmap_sync;

/* The current Email object state -- the since_state cursor a first
 * jmap_sync_emails call needs. On JMAP_OK the returned string is
 * never NULL and never empty: the substrate refuses to parse a state
 * token that fails that check, so a server response that tried to
 * claim an empty state fails the call (JMAP_E_PROTOCOL) instead of
 * succeeding with a hollow value. A non-JMAP_OK return leaves *out
 * untouched, so "no cursor yet" -- this was never called, or the last
 * call on this handle failed -- stays visibly different from a valid
 * cursor: the caller's own initial value (typically NULL) survives to
 * say so, never an empty string standing in for it.
 *
 * The borrow is owned by the client handle and invalidated by the
 * next fallible call on it, exactly like jmap_errmsg; copy the string
 * before making another call if it must outlive that call. */
jmap_status jmap_get_email_state(jmap_client *client,
                                 const char *account_id,
                                 const char **out);

/* One round-trip: changes since the cursor plus both back-referenced
 * fetches. Persist jmap_sync_new_state as the next cursor; when
 * jmap_sync_has_more is 1, call again from that cursor.
 *
 * RFC 8620 section 5.2 lets a record appear in more than one list: one
 * created AND updated since the cursor may surface in both created and
 * updated (dedupe by id when merging); one updated AND destroyed may
 * surface in both jmap_sync_destroyed_at and updated -- destroyed wins,
 * since applying updated after destroyed would resurrect it.
 *
 * JMAP_E_METHOD on this call is routinely cannotCalculateChanges
 * (jmap_errtype distinguishes it from every other method error): the
 * cursor is too old for the server to diff from. There is no partial
 * recovery -- discard any local state built from this cursor and
 * re-bootstrap via jmap_get_email_state. */
jmap_status jmap_sync_emails(jmap_client *client,
                             const char *account_id,
                             const char *since_state,
                             jmap_sync **out);
void jmap_sync_free(jmap_sync *sync);

/* Both always non-NULL and non-empty on a live handle, for the same
 * reason jmap_get_email_state's value is: the substrate never carries
 * an empty state token past decode. Unlike that borrow, these belong
 * to the sync object itself, not the client -- they stay valid across
 * any later call on the client that produced them, until jmap_sync_free
 * releases this handle. */
const char *jmap_sync_old_state(const jmap_sync *s);
const char *jmap_sync_new_state(const jmap_sync *s);
/* 1 or 0. 0 for a NULL handle too, indistinguishable from "delta
 * complete" -- the same convention every other pure-read accessor in
 * this file follows. */
int jmap_sync_has_more(const jmap_sync *s);
/* Email ids destroyed since the cursor. NULL out of range. The borrow
 * lives until jmap_sync_free. */
size_t jmap_sync_destroyed_count(const jmap_sync *s);
const char *jmap_sync_destroyed_at(const jmap_sync *s, size_t i);
/* Borrowed email views owned by the sync object: valid until
 * jmap_sync_free, never freed by the caller. Metadata only -- fetched
 * with no body content, so jmap_email_text_body is NULL for every
 * element of both. Fetch bodies separately with jmap_get_emails, using
 * the ids read off these views. */
const jmap_emails *jmap_sync_created(const jmap_sync *s);
const jmap_emails *jmap_sync_updated(const jmap_sync *s);

/* --- Send --------------------------------------------------------------- */

typedef struct jmap_message jmap_message;
typedef struct jmap_send_result jmap_send_result;

/* A message is built one named value at a time, so no two values can
 * be transposed at the call site and a value the surface learns to
 * carry later costs one enum member rather than one more entry point.
 * Every option here is a value the send itself accepts; there is no
 * placeholder for a field it cannot carry. */
typedef enum {
  JMAP_MSG_IDENTITY_ID    = 0, /* string: the sending Identity id */
  JMAP_MSG_DRAFTS_MAILBOX = 1, /* string: mailbox the draft is made in */
  JMAP_MSG_SENT_MAILBOX   = 2, /* string: mailbox it moves to once sent */
  JMAP_MSG_FROM           = 3, /* string: the sender's address */
  JMAP_MSG_TO             = 4, /* string, list-valued: a To recipient */
  JMAP_MSG_CC             = 5, /* string, list-valued: a Cc recipient */
  JMAP_MSG_BCC            = 6, /* string, list-valued: a Bcc recipient */
  JMAP_MSG_SUBJECT        = 7, /* string: the Subject header */
  JMAP_MSG_BODY           = 8  /* string: the text/plain body */
  /* Pre-1.0: these members are not frozen, but CI snapshots this
   * file, so a change to them is deliberate. */
} jmap_message_opt;

jmap_status jmap_message_new(jmap_message **out);
/* NULL is a no-op. Freeing after jmap_send has consumed the message is
 * correct: the call copies what it needs. */
void jmap_message_free(jmap_message *message);

/* Typed option setter (the sqlite3_bind_* discipline): every option
 * above is a string, so one setter covers the surface; an option of
 * another type would arrive as its own setter rather than widening
 * this one. An unrecognised option or a NULL value is JMAP_E_MISUSE; a
 * value of the right type that is not a legal JMAP value -- an id that
 * is not an id -- is JMAP_E_VALIDATION and leaves the message
 * unchanged. Calling this twice for the SAME option replaces the
 * earlier value outright -- on the three list-valued roles that means
 * the WHOLE list is replaced by the single address supplied. This verb
 * never accumulates; jmap_message_add_str is how a list grows.
 *
 * Ids are parsed here; addresses are not. The send owns the address
 * parse (the headers and the RFC 5321 envelope are built from the same
 * strings), so re-parsing them here would duplicate a check the
 * library already performs: a malformed address is JMAP_E_VALIDATION
 * from jmap_send, not from this call.
 *
 * The message carries no error slot of its own, so this status is the
 * whole diagnosis for which setter failed -- attribution is
 * code-granular, exactly as it is for jmap_query_set_str. */
jmap_status jmap_message_set_str(jmap_message *message,
                                 jmap_message_opt opt,
                                 const char *value);

/* Appends one address to a list-valued role. Append is its own verb,
 * as curl_slist_append is its own function beside curl_easy_setopt,
 * so neither verb changes meaning depending on the option it was
 * handed: set always replaces, add always extends. Only JMAP_MSG_TO,
 * JMAP_MSG_CC and JMAP_MSG_BCC hold lists; add_str on any of the six
 * single-valued options is JMAP_E_MISUSE, as are an unrecognised
 * option, a NULL message and a NULL value. Appending to a role no
 * setter has named yet starts that role's list with this address, so
 * a caller need not seed it with a set first. */
jmap_status jmap_message_add_str(jmap_message *message,
                                 jmap_message_opt opt,
                                 const char *value);

/* Creates the draft in JMAP_MSG_DRAFTS_MAILBOX with the $draft keyword
 * and an inline text/plain body, submits it from JMAP_MSG_IDENTITY_ID,
 * and asks the server to move it into JMAP_MSG_SENT_MAILBOX and drop
 * $draft once the submission succeeds (RFC 8621 section 7.5). That is
 * one request, not three.
 *
 * message must not be NULL, and JMAP_MSG_IDENTITY_ID,
 * JMAP_MSG_DRAFTS_MAILBOX, JMAP_MSG_SENT_MAILBOX, JMAP_MSG_FROM and at
 * least one of JMAP_MSG_TO / JMAP_MSG_CC / JMAP_MSG_BCC must be set. A
 * message missing any of them is JMAP_E_MISUSE, refused before any network
 * traffic; the message has no error slot, so jmap_errmsg on the CLIENT
 * names the option that is unset.
 *
 * When none of JMAP_MSG_TO / JMAP_MSG_CC / JMAP_MSG_BCC is set, that name
 * is JMAP_MSG_TO, standing for the whole group -- not a claim that
 * JMAP_MSG_TO alone would satisfy the requirement.
 *
 * JMAP_MSG_SUBJECT and JMAP_MSG_BODY are optional and default to empty.
 *
 * The submission envelope's recipients are the union of To, Cc and Bcc,
 * and the server removes the Bcc header field during delivery
 * (RFC 8621 section 7.5).
 *
 * Unlike jmap_query_emails, a NULL message is not a legal default: an
 * unfiltered query is a real request, an unaddressed send is not. */
jmap_status jmap_send(jmap_client *client, const char *account_id,
                      const jmap_message *message,
                      jmap_send_result **out);
void jmap_send_result_free(jmap_send_result *result);

/* Both are non-NULL on a live handle: a send that could not report both
 * server-assigned ids did not return JMAP_OK. NULL for a NULL handle,
 * as every other pure-read accessor in this file. The borrows live
 * until jmap_send_result_free. */
const char *jmap_send_result_email_id(const jmap_send_result *r);
const char *jmap_send_result_submission_id(const jmap_send_result *r);

#ifdef __cplusplus
}
#endif
#endif /* JMAP_CLIENT_H */
