/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
/*
 * jmap_client is the C API of the jmap-client library. It speaks JMAP,
 * as defined by RFC 8620 and RFC 8621.
 *
 * The rules here apply to the whole API. Each declaration below adds
 * its own details.
 *
 * Call jmap_init() once per process, before anything else. Only
 * jmap_strerror() and jmap_version() work before that call.
 *
 * Every function that can fail returns a jmap_status. Results come back
 * through out-parameters. jmap_errmsg() gives readable text for the
 * last error on a client.
 *
 * The library owns everything its read accessors return. A returned
 * const char *, and a returned pointer to an object such as
 * jmap_mailbox or jmap_email, is a borrow. It stays valid until the
 * handle that produced it is freed. Do not free a borrow. Objects are
 * released only by their paired jmap_*_free function. The borrows from
 * jmap_errmsg(), jmap_errtype() and jmap_get_email_state() have a
 * shorter life. The next call that can fail on the same client replaces
 * them.
 *
 * Use a handle from one thread at a time. To move a handle to another
 * thread, stop using it on the old thread first.
 *
 * This header is the ABI. The library is pre-1.0, as the version macros
 * below say. The C ABI may still change, and there is no compatibility
 * promise yet. But nothing here changes by accident. A summary of every
 * declaration, type and macro in this file is stored with the library's
 * source code, and an automatic check compares this file against that
 * summary. A change to a type, an enum value or a macro therefore fails
 * that check until someone updates the summary on purpose.
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
  JMAP_E_VALIDATION = 1, /* the caller passed invalid input */
  JMAP_E_TRANSPORT  = 2, /* network, TLS, timeout or HTTP status */
  JMAP_E_REQUEST    = 3, /* the whole request was rejected (RFC 7807) */
  JMAP_E_SESSION    = 4, /* the session lacks a capability we need */
  JMAP_E_MISUSE     = 5, /* caller bug: NULL argument, wrong handle */
  JMAP_E_PROTOCOL   = 6, /* malformed response, or not valid JMAP */
  JMAP_E_METHOD     = 7, /* the whole method call returned an error */
  JMAP_E_SET        = 8  /* the server refused the one new object */
  /* These values are not frozen yet, but they never change by
   * accident. See the note on the ABI at the top of this file. */
} jmap_status;

/*
 * JMAP_E_METHOD means the server answered the method call with an error
 * instead of a result. Call jmap_errtype() to read the error type
 * string the server sent. RFC 8620 section 3.6.2 describes these
 * errors.
 *
 * JMAP_E_SET means a change that creates exactly one object had that
 * create refused, and the server gave a typed reason (RFC 8620
 * section 5.3). It comes back as the status of the call, and not as an
 * entry in a failure list, because only one object was involved, so
 * there is no list to put it in. jmap_send() is the call in this header
 * that reports a refusal this way. Call jmap_errtype() for that reason
 * too.
 *
 * The two statuses draw their strings from different lists, and the
 * lists overlap. "forbidden" is a method error type in RFC 8620
 * section 3.6.2 and a SetError type in section 5.3, and it means a
 * different thing in each. So the status is not a convenience here.
 * Read it before you compare the string, or you cannot tell which of
 * the two you are holding.
 */

/*
 * jmap_init() prepares the library. Call it once per process, before
 * any other function except jmap_strerror() and jmap_version(). It
 * starts the language runtime, which the library needs because it is a
 * shared object built without a main() of its own. Calling it more than
 * once is safe.
 */
jmap_status jmap_init(void);

/*
 * jmap_cleanup() tears the library down. It is optional, and it belongs
 * at process exit. It is not safe to call while handles are still
 * alive, so free every handle first.
 */
void jmap_cleanup(void);

/*
 * jmap_strerror() returns a fixed description of a status code. The
 * string is never NULL. Do not free it. You may call this before
 * jmap_init().
 */
const char *jmap_strerror(jmap_status code);

/*
 * jmap_version() returns the library version as "MAJOR.MINOR.PATCH".
 * The string is fixed. Do not free it. You may call this before
 * jmap_init().
 */
const char *jmap_version(void);

/* Opaque handles. The struct layouts are never exposed. */
typedef struct jmap_client jmap_client;
typedef struct jmap_transport jmap_transport;

/*
 * jmap_client_new() creates a client for session_url, using Basic
 * authentication. Must be freed with jmap_client_free().
 *
 * Pass NULL for transport to use the built-in HTTP transport. Pass a
 * transport from jmap_transport_new() to supply your own HTTP.
 *
 * This call does no network IO. The client fetches the JMAP session on
 * first use, so a server you cannot reach shows up as an error on the
 * first operation, not here.
 *
 * On failure *out is left alone, and the returned status is the whole
 * report. No handle exists yet to ask.
 */
jmap_status jmap_client_new(const char *session_url,
                            const char *username,
                            const char *password,
                            jmap_transport *transport,
                            jmap_client **out);

/*
 * jmap_client_free() releases the client and closes its transport.
 * Passing NULL does nothing.
 */
void jmap_client_free(jmap_client *client);

/*
 * jmap_errmsg() returns readable text for the most recent error on this
 * client. It returns "no error" when the last call succeeded.
 *
 * The client owns the string. Do not free it. It stays valid until the
 * next call that can fail on the same client, or until
 * jmap_client_free(), whichever comes first. Copy it if you need it
 * later.
 */
const char *jmap_errmsg(const jmap_client *client);

/*
 * jmap_errtype() returns the "type" string the server sent for the last
 * typed error on this client. Two statuses carry one.
 *
 * After JMAP_E_METHOD it is a method error type, for example
 * "unknownMethod". RFC 8620 section 3.6.2 gives the shape of these
 * errors and the types any method may return; individual methods define
 * more of their own, such as the "cannotCalculateChanges" that
 * jmap_sync_emails() can meet.
 *
 * After JMAP_E_SET it is the reason the one create was refused, for
 * example "overQuota" or "tooLarge". RFC 8620 section 5.3 does the same
 * for these: a list any record type may draw on, which individual
 * methods extend.
 *
 * Read the status first. It is what says which of the two lists the
 * string came from, and the lists overlap: "forbidden" is on both, and
 * means a different thing on each, so the string alone will not tell
 * you. Use jmap_errmsg() for text a person reads, and this function for
 * a value your code compares. The library carries the type off the wire
 * without changing it, so a type one vendor invented reaches C intact.
 * jmap_set_result_failure_type_at() works the same way, for the
 * refusals that come back as data on a result instead of as a status.
 *
 * It returns NULL when the last call did not fail with either of those
 * two statuses. That covers a NULL client, no error at all, and a
 * failure with any other status such as JMAP_E_VALIDATION or
 * JMAP_E_SESSION. When the result is not NULL, it is never the empty
 * string. So you can never confuse "no type at all" with "a type that
 * is empty".
 *
 * The borrow lives as long as the one from jmap_errmsg(). The client
 * owns it. The next call that can fail on the same client, or
 * jmap_client_free(), makes it invalid.
 */
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

/*
 * jmap_send_fn performs one HTTP exchange.
 *
 * The library owns url, body and authorization. They are never NULL. A
 * GET carries an empty body string, not a NULL one. They are valid only
 * while the call runs. Copy anything you need to keep after you return.
 *
 * To report success, return JMAP_TRANSPORT_OK, set *out_http_status,
 * and hand back *out_content_type and *out_body as buffers from
 * malloc(). The library copies both, then frees them with free(). For
 * any other return value the library ignores the out-parameters.
 *
 * Allocate *out_content_type and *out_body with the same C runtime this
 * library links against. If the two differ, say two different Windows C
 * runtimes, or a debug one and a release one, the free() the library
 * makes is undefined behaviour.
 *
 * The callback must return normally. Do not leave it with longjmp(),
 * and do not let a C++ exception escape it. The library hands userdata
 * back unchanged and never looks inside it.
 */
typedef jmap_transport_code (*jmap_send_fn)(void *userdata,
                                            jmap_http_method method,
                                            const char *url,
                                            const char *body,
                                            const char *authorization,
                                            int *out_http_status,
                                            char **out_content_type,
                                            char **out_body);

/*
 * jmap_close_fn fires exactly once, when the last reference to the
 * transport goes away. That is jmap_transport_free() or
 * jmap_client_free(), whichever happens last.
 */
typedef void (*jmap_close_fn)(void *userdata);

/*
 * jmap_transport_new() wraps your callbacks in a transport handle. Must
 * be freed with jmap_transport_free().
 *
 * Pass NULL for close when there is nothing to release. One transport
 * serves at most one client. A second client that tries to attach it
 * gets JMAP_E_MISUSE.
 */
jmap_status jmap_transport_new(jmap_send_fn send,
                               jmap_close_fn close,
                               void *userdata,
                               jmap_transport **out);

/*
 * jmap_transport_free() drops the caller's reference to the transport.
 * When a client holds the other reference, the transport lives until
 * jmap_client_free(). Passing NULL does nothing.
 */
void jmap_transport_free(jmap_transport *transport);

/* --- Session and accounts ------------------------------------------- */
/*
 * These functions fetch the JMAP session on first use and keep it. That
 * is why they take a client that is not const. Expect transport and
 * protocol statuses from that first call.
 *
 * Account ids come back in the order strcmp() gives, smallest first.
 * The order holds until jmap_client_free().
 */

/*
 * jmap_client_primary_account() returns the account RFC 8621 names as
 * the primary one for mail. When that account does not advertise mail,
 * the library falls back to the mail-capable account that sorts first.
 * It returns JMAP_E_SESSION when no account advertises mail. The client
 * owns the returned string.
 */
jmap_status jmap_client_primary_account(jmap_client *client,
                                        const char **out);

jmap_status jmap_client_account_count(jmap_client *client, size_t *out);

/*
 * jmap_client_account_at() returns account number i. It only reads
 * cached data and never talks to the server. It returns NULL when i is
 * out of range, and when no fetch has succeeded yet. Call
 * jmap_client_account_count() first.
 *
 * Every accessor in this header that takes an index returns NULL for an
 * index that is out of range. Any index that is not below the count is
 * out of range, including very large ones such as SIZE_MAX.
 */
const char *jmap_client_account_at(const jmap_client *client, size_t i);

/* --- Wire debugging -------------------------------------------------- */

typedef enum {
  JMAP_WIRE_SEND    = 0,
  JMAP_WIRE_RECEIVE = 1
} jmap_wire_direction;

/*
 * jmap_debug_fn fires once per direction for each HTTP exchange the
 * client attempts. That is at most two calls per exchange, never more.
 *
 * A send fire does not promise a receive fire after it. The library
 * builds the request and fires the send before it checks the request
 * size, and before it calls the transport. So an oversized request, a
 * session URL it could not resolve, or a transport failure can leave a
 * send with no matching receive.
 *
 * bytes is never NULL, even when len is 0. The GET that fetches the
 * session has an empty body, and that is the very first fire every
 * client makes. So memcpy(dst, bytes, len) is always well defined.
 *
 * bytes comes with a length and is not NUL-terminated. Do not treat it
 * as a C string. The library owns it for the length of the call only.
 * Copy it if you keep it.
 *
 * The callback must return normally, under the same rule as
 * jmap_send_fn above, and like jmap_send_fn it fires while an exchange
 * is still running. If you free the client from inside the callback,
 * the library reads freed memory once the callback returns. The caller
 * must avoid that. The library does not guard against it.
 */
typedef void (*jmap_debug_fn)(void *userdata,
                              jmap_wire_direction direction,
                              const uint8_t *bytes,
                              size_t len);

/*
 * jmap_set_debug_callback() installs fn on the client. Pass NULL for fn
 * to remove it. The library hands userdata back unchanged.
 */
jmap_status jmap_set_debug_callback(jmap_client *client,
                                    jmap_debug_fn fn,
                                    void *userdata);

/* --- Mailboxes -------------------------------------------------------- */

typedef struct jmap_mailboxes jmap_mailboxes;
typedef struct jmap_mailbox jmap_mailbox; /* a borrow, never freed */

/*
 * The role a mailbox plays. JMAP_ROLE_NONE means the mailbox has no
 * role. JMAP_ROLE_UNKNOWN means the server named a role this version of
 * the library does not know. Read the string the server sent with
 * jmap_mailbox_role_identifier().
 *
 * These values are not frozen yet, but they never change by accident.
 * See the note on the ABI at the top of this file.
 */
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

/*
 * jmap_get_mailboxes() fetches the mailboxes of the account. Must be
 * freed with jmap_mailboxes_free().
 */
jmap_status jmap_get_mailboxes(jmap_client *client,
                               const char *account_id,
                               jmap_mailboxes **out);
void jmap_mailboxes_free(jmap_mailboxes *mailboxes);

size_t jmap_mailboxes_count(const jmap_mailboxes *mailboxes);
/* Returns NULL when i is out of range. The borrow lives until
 * jmap_mailboxes_free(). */
const jmap_mailbox *jmap_mailboxes_at(const jmap_mailboxes *mailboxes,
                                      size_t i);

const char *jmap_mailbox_id(const jmap_mailbox *mb);
const char *jmap_mailbox_name(const jmap_mailbox *mb);
jmap_mailbox_role jmap_mailbox_role_get(const jmap_mailbox *mb);
/* Returns the role string the server sent, or "" when the mailbox has
 * no role. */
const char *jmap_mailbox_role_identifier(const jmap_mailbox *mb);
/* Returns NULL when the mailbox is at the top level. */
const char *jmap_mailbox_parent_id(const jmap_mailbox *mb);
int64_t jmap_mailbox_total_emails(const jmap_mailbox *mb);
int64_t jmap_mailbox_unread_emails(const jmap_mailbox *mb);
/* Returns 1 or 0. */
int jmap_mailbox_is_subscribed(const jmap_mailbox *mb);
int jmap_mailbox_has_right(const jmap_mailbox *mb, jmap_mailbox_right r);

/* --- Emails ----------------------------------------------------------- */

typedef struct jmap_emails jmap_emails;
typedef struct jmap_email jmap_email; /* a borrow, never freed */

/*
 * jmap_get_emails() fetches the named emails with their text bodies.
 * ids points to an array of n id strings, as other calls return them.
 * Must be freed with jmap_emails_free().
 */
jmap_status jmap_get_emails(jmap_client *client,
                            const char *account_id,
                            const char *const *ids,
                            size_t n,
                            jmap_emails **out);
void jmap_emails_free(jmap_emails *emails);

size_t jmap_emails_count(const jmap_emails *emails);
/* Returns NULL when i is out of range. The borrow lives until
 * jmap_emails_free(). */
const jmap_email *jmap_emails_at(const jmap_emails *emails, size_t i);
size_t jmap_emails_notfound_count(const jmap_emails *emails);
/* Returns NULL when i is out of range. The borrow lives until
 * jmap_emails_free(). */
const char *jmap_emails_notfound_at(const jmap_emails *emails, size_t i);

/*
 * These getters return NULL when the server left the field out.
 * jmap_email_preview() is the one exception. RFC 8621 section 4.1.4
 * makes preview a field the server always sets, and it defaults to "",
 * so jmap_email_preview() is never NULL for a live handle.
 */
const char *jmap_email_id(const jmap_email *e);
const char *jmap_email_thread_id(const jmap_email *e);
const char *jmap_email_subject(const jmap_email *e);
/*
 * jmap_email_from_email() and jmap_email_from_name() return the first
 * From address, which is what you usually display. When the server
 * sends "from": [] you cannot tell it apart from a missing from field.
 * Both functions return NULL either way.
 */
const char *jmap_email_from_email(const jmap_email *e);
const char *jmap_email_from_name(const jmap_email *e);
const char *jmap_email_preview(const jmap_email *e);
/* Returns an RFC 3339 UTC date string. */
const char *jmap_email_received_at(const jmap_email *e);
/* Returns the decoded text/plain body, when one was fetched. */
const char *jmap_email_text_body(const jmap_email *e);
int jmap_email_has_attachment(const jmap_email *e);

/* --- Email query -------------------------------------------------------- */

typedef struct jmap_query jmap_query;

typedef enum {
  JMAP_Q_IN_MAILBOX = 0, /* string: a mailbox id */
  JMAP_Q_TEXT       = 1, /* string: text to search for */
  JMAP_Q_LIMIT      = 2, /* u32: result limit, 0 = server default */
  JMAP_Q_READ_STATE = 3, /* u32: a jmap_read_state value */
  JMAP_Q_SORT       = 4  /* u32: a jmap_sort value */
  /* These values are not frozen yet, but they never change by
   * accident. See the note on the ABI at the top of this file. */
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

/*
 * jmap_query_new() creates an empty query. Must be freed with
 * jmap_query_free().
 */
jmap_status jmap_query_new(jmap_query **out);
/*
 * jmap_query_free() releases the query. Passing NULL does nothing. It
 * is correct to free a query after jmap_query_emails() has used it,
 * because that call copies what it needs.
 */
void jmap_query_free(jmap_query *query);

/*
 * jmap_query_set_str() and jmap_query_set_u32() each set one query
 * option. The list above says which type each option takes.
 *
 * You get JMAP_E_MISUSE when you use the setter for the wrong type,
 * when you pass a NULL string, and when you pass a value the library
 * does not know, such as an option outside jmap_query_opt or a number
 * outside jmap_read_state or jmap_sort. A query has no error slot of
 * its own, so the status a setter returns is the only report you get
 * about that setter.
 *
 * The setters parse and check the value straight away, not when the
 * query runs. A value of the right type that is not legal in JMAP, such
 * as a malformed mailbox id, returns JMAP_E_VALIDATION and leaves the
 * query as it was.
 *
 * Setting the same option twice replaces the earlier value.
 *
 * JMAP_Q_IN_MAILBOX, JMAP_Q_TEXT and JMAP_Q_READ_STATE each set one
 * property of a single filter condition, so all three narrow the same
 * query together. JMAP_Q_LIMIT and JMAP_Q_SORT sit outside that
 * condition, in slots of their own.
 */
jmap_status jmap_query_set_str(jmap_query *query, jmap_query_opt opt,
                               const char *value);
jmap_status jmap_query_set_u32(jmap_query *query, jmap_query_opt opt,
                               uint32_t value);

/*
 * jmap_query_emails() runs Email/query (RFC 8621 section 4.4), then
 * fetches the text bodies of the matching records with Email/get
 * (RFC 8621 section 4.2). Both happen in one round trip. Must be freed
 * with jmap_emails_free().
 *
 * query may be NULL. That asks for no filter, no sort and the server's
 * default paging. It is a legal request, not a special case.
 */
jmap_status jmap_query_emails(jmap_client *client,
                              const char *account_id,
                              const jmap_query *query,
                              jmap_emails **out);

/* --- Threads and identities -------------------------------------------- */

typedef struct jmap_threads jmap_threads;
typedef struct jmap_thread jmap_thread; /* a borrow, never freed */
typedef struct jmap_identities jmap_identities;
typedef struct jmap_identity jmap_identity; /* a borrow, never freed */

/*
 * jmap_get_threads() fetches the named threads. ids points to an array
 * of n thread id strings. Must be freed with jmap_threads_free().
 */
jmap_status jmap_get_threads(jmap_client *client, const char *account_id,
                             const char *const *ids, size_t n,
                             jmap_threads **out);
void jmap_threads_free(jmap_threads *threads);
size_t jmap_threads_count(const jmap_threads *threads);
/* Returns NULL when i is out of range. The borrow lives until
 * jmap_threads_free(). */
const jmap_thread *jmap_threads_at(const jmap_threads *threads, size_t i);
const char *jmap_thread_id(const jmap_thread *th);
size_t jmap_thread_email_count(const jmap_thread *th);
/*
 * jmap_thread_email_at() returns email id number i, or NULL when i is
 * out of range. As the typedef above says, th is itself a borrow into
 * the threads handle, and so is this string. Both live until
 * jmap_threads_free(). A single thread has no lifetime of its own.
 */
const char *jmap_thread_email_at(const jmap_thread *th, size_t i);

/*
 * jmap_get_identities() fetches the identities of the account. Must be
 * freed with jmap_identities_free().
 */
jmap_status jmap_get_identities(jmap_client *client,
                                const char *account_id,
                                jmap_identities **out);
void jmap_identities_free(jmap_identities *identities);
size_t jmap_identities_count(const jmap_identities *identities);
/* Returns NULL when i is out of range. The borrow lives until
 * jmap_identities_free(). */
const jmap_identity *jmap_identities_at(const jmap_identities *identities,
                                        size_t i);
const char *jmap_identity_id(const jmap_identity *ident);
const char *jmap_identity_name(const jmap_identity *ident);
const char *jmap_identity_email(const jmap_identity *ident);

/* --- Email writes ----------------------------------------------------- */

typedef struct jmap_set_result jmap_set_result;

/*
 * jmap_mark_read(), jmap_mark_unread(), jmap_move_emails() and
 * jmap_destroy_emails() each take an array of n email ids. Each hands
 * back a jmap_set_result that must be freed with
 * jmap_set_result_free().
 *
 * A refusal of one id is data on the result object, not an error. The
 * returned status reports failure of the whole call only.
 *
 * jmap_mark_read(), jmap_mark_unread() and jmap_move_emails() reject an
 * empty array and duplicate ids with JMAP_E_VALIDATION, before they
 * send anything. jmap_destroy_emails() accepts both. An empty array is
 * legal on the wire and destroys nothing. Duplicate ids go to the
 * server as given, and the server answers each one on its own, as
 * RFC 8620 section 5.3 requires. Destroy has no client-side check that
 * rejects a repeat.
 *
 * The updated, destroyed and failure lists on the result follow the
 * order of the server's own answer, not the order you submitted the ids
 * in. That order can differ from one call to the next. To line results
 * up with the array you submitted, match by id. Never match by
 * position.
 */
jmap_status jmap_mark_read(jmap_client *client, const char *account_id,
                           const char *const *ids, size_t n,
                           jmap_set_result **out);
jmap_status jmap_mark_unread(jmap_client *client, const char *account_id,
                             const char *const *ids, size_t n,
                             jmap_set_result **out);
/*
 * jmap_move_emails() replaces the whole mailbox membership of every
 * email it is given. Afterwards each email is in mailbox_id and in no
 * other mailbox.
 */
jmap_status jmap_move_emails(jmap_client *client, const char *account_id,
                             const char *const *ids, size_t n,
                             const char *mailbox_id,
                             jmap_set_result **out);
jmap_status jmap_destroy_emails(jmap_client *client, const char *account_id,
                                const char *const *ids, size_t n,
                                jmap_set_result **out);
void jmap_set_result_free(jmap_set_result *result);

size_t jmap_set_result_updated_count(const jmap_set_result *r);
/* Returns NULL when i is out of range. The borrow lives until
 * jmap_set_result_free(). */
const char *jmap_set_result_updated_at(const jmap_set_result *r, size_t i);
size_t jmap_set_result_destroyed_count(const jmap_set_result *r);
/* Returns NULL when i is out of range. The borrow lives until
 * jmap_set_result_free(). */
const char *jmap_set_result_destroyed_at(const jmap_set_result *r, size_t i);
size_t jmap_set_result_failure_count(const jmap_set_result *r);
/* Returns NULL when i is out of range. The borrow lives until
 * jmap_set_result_free(). */
const char *jmap_set_result_failure_id_at(const jmap_set_result *r, size_t i);
/* Returns the SetError type the server sent, such as "notFound" or
 * "forbidden". RFC 8620 section 5.3 defines these strings. Returns
 * NULL when i is out of range. The borrow lives until
 * jmap_set_result_free(). */
const char *jmap_set_result_failure_type_at(const jmap_set_result *r,
                                            size_t i);

/* --- Vacation response ------------------------------------------------ */

typedef struct jmap_vacation jmap_vacation;
typedef struct jmap_vacation_update jmap_vacation_update;

typedef enum {
  JMAP_VACATION_DISABLED = 0,
  JMAP_VACATION_ENABLED  = 1
} jmap_vacation_state;

/*
 * jmap_get_vacation() reads the one vacation record the account has.
 * RFC 8621 section 8.1 requires the server to return exactly one
 * record. Any other count returns JMAP_E_PROTOCOL, because the library
 * will not guess which record to show you. Must be freed with
 * jmap_vacation_free().
 */
jmap_status jmap_get_vacation(jmap_client *client, const char *account_id,
                              jmap_vacation **out);
void jmap_vacation_free(jmap_vacation *vacation);
/*
 * jmap_vacation_is_enabled() returns 1 when the vacation response is on
 * and 0 when it is off. JMAP_VACATION_DISABLED is 0 and
 * JMAP_VACATION_ENABLED is 1, so you can pass what this returns
 * straight to jmap_vacation_update_set_enabled().
 */
int jmap_vacation_is_enabled(const jmap_vacation *v);
/* Returns NULL when the field is not set. */
const char *jmap_vacation_subject(const jmap_vacation *v);
const char *jmap_vacation_text_body(const jmap_vacation *v);

/*
 * jmap_vacation_update_new() creates an empty update. Must be freed
 * with jmap_vacation_update_free(). The three setters below fill it in,
 * one property each, and each takes its value as you call it. The query
 * options work the same way.
 *
 * A property that no setter names is left untouched by the update. A
 * setter called with NULL clears that property to JSON null, which
 * RFC 8621 section 8 allows for subject and textBody. Those are two
 * different requests, and only the setters can tell them apart. Calling
 * a setter twice replaces the earlier value.
 *
 * Each setter returns JMAP_OK or JMAP_E_MISUSE. You get JMAP_E_MISUSE
 * for a NULL handle, for a state that is neither JMAP_VACATION_DISABLED
 * nor JMAP_VACATION_ENABLED, and for a call made before jmap_init(). A
 * string value is never invalid on its own, so no validation status
 * comes out of these calls. An update has no error slot of its own, so
 * the status a setter returns is the only report you get.
 *
 * This version has no setters for fromDate, toDate and htmlBody. A JMAP
 * patch leaves a property it does not mention untouched. So turning a
 * response on through these setters keeps whatever dates the record
 * already holds, even dates another client wrote. RFC 8621 section 8
 * ties "effective immediately" and "effective indefinitely" to a null
 * fromDate and toDate on the record itself, not to a property the patch
 * says nothing about. The response is immediate and open-ended only
 * when the record's own fromDate and toDate are already null. A later
 * version may add setters for them.
 */
jmap_status jmap_vacation_update_new(jmap_vacation_update **out);
jmap_status jmap_vacation_update_set_enabled(jmap_vacation_update *update,
                                             jmap_vacation_state state);
jmap_status jmap_vacation_update_set_subject(jmap_vacation_update *update,
                                             const char *subject);
jmap_status jmap_vacation_update_set_text_body(jmap_vacation_update *update,
                                               const char *text_body);
/*
 * jmap_vacation_update_free() releases the update. Passing NULL does
 * nothing. It is correct to free an update after jmap_set_vacation()
 * has used it, because that call copies what it needs.
 */
void jmap_vacation_update_free(jmap_vacation_update *update);

/*
 * jmap_set_vacation() sends the update you built to the account's
 * vacation record. update must not be NULL, and at least one setter
 * must have been called on it. An empty patch returns
 * JMAP_E_VALIDATION and nothing goes to the server. The result must be
 * freed with jmap_set_result_free().
 *
 * JMAP_OK means the call finished. It does not mean the server accepted
 * the change. A refusal comes back as data, as RFC 8620 section 5.3
 * describes. The usual refused update is JMAP_OK with
 * jmap_set_result_updated_count() == 0 and
 * jmap_set_result_failure_count() == 1, and you read the reason with
 * jmap_set_result_failure_type_at(). Read the counts before you index
 * either list. The status does not promise that either list holds
 * anything.
 *
 * jmap_set_result_destroyed_count() is always 0 here, because this
 * update creates and destroys nothing.
 */
jmap_status jmap_set_vacation(jmap_client *client,
                              const char *account_id,
                              const jmap_vacation_update *update,
                              jmap_set_result **out);

/* --- Incremental sync ------------------------------------------------- */

typedef struct jmap_sync jmap_sync;

/*
 * jmap_get_email_state() returns the current Email state string. That
 * is the since_state cursor your first jmap_sync_emails() call needs.
 *
 * On JMAP_OK the string is never NULL and never empty. The library
 * refuses to parse an empty state token, so a server that claims an
 * empty state fails the call with JMAP_E_PROTOCOL instead of handing
 * you a hollow value.
 *
 * When the call does not return JMAP_OK it leaves *out alone. So "no
 * cursor yet", meaning you never called this or the last call on this
 * handle failed, always looks different from a real cursor. Your own
 * starting value, usually NULL, survives to say so. An empty string
 * never stands in for it.
 *
 * The client owns the string. The next call that can fail on the same
 * client replaces it, exactly as with jmap_errmsg(). Copy it before you
 * make another call if it must outlive that call.
 */
jmap_status jmap_get_email_state(jmap_client *client,
                                 const char *account_id,
                                 const char **out);

/*
 * jmap_sync_emails() asks for the changes since the cursor and fetches
 * the changed records, all in one round trip. Must be freed with
 * jmap_sync_free().
 *
 * Save jmap_sync_new_state() as your next cursor. When
 * jmap_sync_has_more() returns 1, call again from that cursor.
 *
 * RFC 8620 section 5.2 lets one record appear in more than one list. A
 * record created and then updated since the cursor can appear in both
 * created and updated, so drop duplicates by id when you merge. A
 * record updated and then destroyed can appear in both updated and
 * jmap_sync_destroyed_at(). Destroyed wins there, because applying the
 * update after the destroy would bring the record back.
 *
 * JMAP_E_METHOD from this call is often cannotCalculateChanges, which
 * means the server can no longer work out the changes since your
 * cursor. Call jmap_errtype() to tell that apart from any other method
 * error. There is no partial recovery. Throw away the local state you
 * built from this cursor and start again from jmap_get_email_state().
 */
jmap_status jmap_sync_emails(jmap_client *client,
                             const char *account_id,
                             const char *since_state,
                             jmap_sync **out);
void jmap_sync_free(jmap_sync *sync);

/*
 * jmap_sync_old_state() and jmap_sync_new_state() are never NULL and
 * never empty for a live handle, for the same reason the value from
 * jmap_get_email_state() is: the library never carries an empty state
 * token past decoding. These two borrows belong to the sync object, not
 * to the client, so they stay valid across later calls on the client
 * that produced them. They live until jmap_sync_free().
 */
const char *jmap_sync_old_state(const jmap_sync *s);
const char *jmap_sync_new_state(const jmap_sync *s);
/*
 * jmap_sync_has_more() returns 1 or 0. It also returns 0 for a NULL
 * handle, which you cannot tell apart from "no more changes". Every
 * other read accessor in this header follows the same rule.
 */
int jmap_sync_has_more(const jmap_sync *s);
/*
 * jmap_sync_destroyed_count() and jmap_sync_destroyed_at() give the ids
 * of the emails destroyed since the cursor. jmap_sync_destroyed_at()
 * returns NULL when i is out of range. The borrow lives until
 * jmap_sync_free().
 */
size_t jmap_sync_destroyed_count(const jmap_sync *s);
const char *jmap_sync_destroyed_at(const jmap_sync *s, size_t i);
/*
 * jmap_sync_created() and jmap_sync_updated() return lists of emails
 * the sync object owns. They are valid until jmap_sync_free(). Do not
 * free them.
 *
 * These emails carry metadata only. The library fetched them with no
 * body content, so jmap_email_text_body() returns NULL for every one of
 * them. To read the bodies, take the ids off these emails and pass them
 * to jmap_get_emails().
 */
const jmap_emails *jmap_sync_created(const jmap_sync *s);
const jmap_emails *jmap_sync_updated(const jmap_sync *s);

/* --- Send --------------------------------------------------------------- */

typedef struct jmap_message jmap_message;
typedef struct jmap_send_result jmap_send_result;

/*
 * The values a message carries. You set them one at a time, each by
 * name, so the call site cannot swap two of them by mistake, and a new
 * value costs one enum member instead of one more function. Every
 * option here is a value the send accepts. There is no option for a
 * field the send cannot carry.
 */
typedef enum {
  JMAP_MSG_IDENTITY_ID    = 0, /* string: id of the sending identity */
  JMAP_MSG_DRAFTS_MAILBOX = 1, /* string: mailbox the draft is made in */
  JMAP_MSG_SENT_MAILBOX   = 2, /* string: mailbox it moves to once sent */
  JMAP_MSG_FROM           = 3, /* string: the sender's address */
  JMAP_MSG_TO             = 4, /* string, holds a list: a To recipient */
  JMAP_MSG_CC             = 5, /* string, holds a list: a Cc recipient */
  JMAP_MSG_BCC            = 6, /* string, holds a list: a Bcc recipient */
  JMAP_MSG_SUBJECT        = 7, /* string: the Subject header */
  JMAP_MSG_BODY           = 8  /* string: the text/plain body */
  /* These values are not frozen yet, but they never change by
   * accident. See the note on the ABI at the top of this file. */
} jmap_message_opt;

/*
 * jmap_message_new() creates an empty message. Must be freed with
 * jmap_message_free().
 */
jmap_status jmap_message_new(jmap_message **out);
/*
 * jmap_message_free() releases the message. Passing NULL does nothing.
 * It is correct to free a message after jmap_send() has used it,
 * because that call copies what it needs.
 */
void jmap_message_free(jmap_message *message);

/*
 * jmap_message_set_str() sets one message option. Every option above
 * takes a string, so one setter covers them all. An option of another
 * type would get a setter of its own.
 *
 * An option the library does not know, or a NULL value, returns
 * JMAP_E_MISUSE. A value of the right type that is not legal in JMAP,
 * such as an id that is not an id, returns JMAP_E_VALIDATION and leaves
 * the message as it was.
 *
 * Setting the same option twice replaces the earlier value. On the
 * three options that hold lists, that replaces the whole list with the
 * one address you passed. This function never appends. Use
 * jmap_message_add_str() to grow a list.
 *
 * The library parses ids here. It does not parse addresses here.
 * jmap_send() parses those, because it builds the headers and the
 * RFC 5321 envelope from the same strings, and a check here would
 * repeat one the library already makes. A malformed address returns
 * JMAP_E_VALIDATION from jmap_send(), not from this call.
 *
 * A message has no error slot of its own, so the status this call
 * returns is the only report you get about this setter.
 * jmap_query_set_str() works the same way.
 */
jmap_status jmap_message_set_str(jmap_message *message,
                                 jmap_message_opt opt,
                                 const char *value);

/*
 * jmap_message_add_str() appends one address to an option that holds a
 * list. Appending has a function of its own, so neither verb changes
 * meaning with the option it is given: set always replaces, add always
 * appends.
 *
 * Only JMAP_MSG_TO, JMAP_MSG_CC and JMAP_MSG_BCC hold lists. Calling
 * this on any of the other six options returns JMAP_E_MISUSE, and so do
 * an option the library does not know, a NULL message and a NULL value.
 *
 * You may append to an option that no setter has named yet. That starts
 * the list with this address, so you need not call
 * jmap_message_set_str() first.
 */
jmap_status jmap_message_add_str(jmap_message *message,
                                 jmap_message_opt opt,
                                 const char *value);

/*
 * jmap_send() creates the draft in JMAP_MSG_DRAFTS_MAILBOX with the
 * $draft keyword and an inline text/plain body, submits it from
 * JMAP_MSG_IDENTITY_ID, and asks the server to move it into
 * JMAP_MSG_SENT_MAILBOX and drop $draft once the submission succeeds
 * (RFC 8621 section 7.5). That is one request, not three. The result
 * must be freed with jmap_send_result_free().
 *
 * message must not be NULL. JMAP_MSG_IDENTITY_ID,
 * JMAP_MSG_DRAFTS_MAILBOX, JMAP_MSG_SENT_MAILBOX and JMAP_MSG_FROM must
 * all be set, and so must at least one of JMAP_MSG_TO, JMAP_MSG_CC and
 * JMAP_MSG_BCC. A message missing any of them returns JMAP_E_MISUSE,
 * and nothing goes to the server. A message has no error slot, so call
 * jmap_errmsg() on the client to learn which option is unset.
 *
 * When none of JMAP_MSG_TO, JMAP_MSG_CC and JMAP_MSG_BCC is set, the
 * option named in that message is JMAP_MSG_TO. It stands for the whole
 * group. It does not mean that JMAP_MSG_TO alone would satisfy the
 * requirement.
 *
 * JMAP_MSG_SUBJECT and JMAP_MSG_BODY are optional. Both default to
 * empty.
 *
 * The recipients of the submission envelope are To, Cc and Bcc taken
 * together, and the server removes the Bcc header field when it
 * delivers the message (RFC 8621 section 7.5).
 *
 * message may not be NULL, unlike the query jmap_query_emails() takes.
 * A query with no filter is still a real request. A send with no
 * recipients is not.
 */
jmap_status jmap_send(jmap_client *client, const char *account_id,
                      const jmap_message *message,
                      jmap_send_result **out);
void jmap_send_result_free(jmap_send_result *result);

/*
 * jmap_send_result_email_id() and jmap_send_result_submission_id()
 * return the two ids the server assigned. Both are set for a live
 * handle, because a send that could not report both did not return
 * JMAP_OK. Both return NULL for a NULL handle, as every other read
 * accessor here does. The borrows live until jmap_send_result_free().
 */
const char *jmap_send_result_email_id(const jmap_send_result *r);
const char *jmap_send_result_submission_id(const jmap_send_result *r);

#ifdef __cplusplus
}
#endif
#endif /* JMAP_CLIENT_H */
