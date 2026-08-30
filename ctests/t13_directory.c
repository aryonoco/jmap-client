/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";
static const char *THREAD_GET_JSON = "{\"methodResponses\":[[\"Thread/get\",{\"accountId\":\"A1\",\"state\":\"th-st1\",\"list\":[{\"id\":\"th-1\",\"emailIds\":[\"em-1\",\"em-2\"]}],\"notFound\":[]},\"c0\"]],\"sessionState\":\"s1\"}";
static const char *IDENTITY_GET_JSON = "{\"methodResponses\":[[\"Identity/get\",{\"accountId\":\"A1\",\"state\":\"id-st1\",\"list\":[{\"id\":\"449e1873-830a-4cbd-b884-c8fe8a16d36c\",\"name\":\"Alice\",\"email\":\"alice@example.com\",\"textSignature\":\"\",\"htmlSignature\":\"\",\"mayDelete\":true}],\"notFound\":[]},\"c0\"]],\"sessionState\":\"s1\"}";
static const char *VACATION_GET_JSON = "{\"methodResponses\":[[\"VacationResponse/get\",{\"accountId\":\"A1\",\"state\":\"va-st1\",\"list\":[{\"id\":\"singleton\",\"isEnabled\":true,\"subject\":\"phase-b step-9 OOO\",\"textBody\":\"Out until next sprint.\"}],\"notFound\":[]},\"c0\"]],\"sessionState\":\"s1\"}";
/* Two "singleton" records disagreeing on isEnabled, the second omitting
 * subject/textBody: RFC 8621 §8.1 forbids this shape outright (exactly
 * one VacationResponse object ever exists), so this fixture exists only
 * to prove the library rejects it rather than reading enabled from
 * entry 2 with subject/textBody left over from entry 1 — a value that
 * never existed on the wire. */
static const char *BAD_VACATION_GET_JSON = "{\"methodResponses\":[[\"VacationResponse/get\",{\"accountId\":\"A1\",\"state\":\"va-st2\",\"list\":[{\"id\":\"singleton\",\"isEnabled\":true,\"subject\":\"phase-b step-9 OOO\",\"textBody\":\"Out until next sprint.\"},{\"id\":\"singleton\",\"isEnabled\":false}],\"notFound\":[]},\"c0\"]],\"sessionState\":\"s1\"}";

int main(void) {
  assert(jmap_init() == JMAP_OK);
  const char *bodies[] = { SESSION_JSON, THREAD_GET_JSON,
                           IDENTITY_GET_JSON, VACATION_GET_JSON,
                           BAD_VACATION_GET_JSON };
  canned_state st = { bodies, 5, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);
  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  /* Threads: id plus the member email ids. */
  const char *tids[] = { "th-1" };
  jmap_threads *ths = NULL;
  assert(jmap_get_threads(c, acct, tids, 1, &ths) == JMAP_OK);
  assert(jmap_threads_count(ths) == 1);
  const jmap_thread *th = jmap_threads_at(ths, 0);
  assert(th != NULL && jmap_thread_id(th) != NULL);
  /* SIZE_MAX must not narrow into range: still NULL, never a crash. */
  assert(jmap_threads_at(ths, SIZE_MAX) == NULL);
  assert(jmap_thread_email_count(th) == 2);
  assert(jmap_thread_email_at(th, 0) != NULL);
  assert(jmap_thread_email_at(th, 2) == NULL);
  assert(jmap_thread_email_at(th, SIZE_MAX) == NULL);
  /* A count too large to narrow to Nim's signed int is misuse, not a
   * RangeDefect abort: SIZE_MAX exercises parseIdArray's unsigned-domain
   * bound on n itself, before the loop ever narrows it or touches ids —
   * the same guard t07 already pins via jmap_get_emails, exercised here
   * too so a future change to one caller cannot silently unpin the
   * other. */
  jmap_threads *huge = NULL;
  assert(jmap_get_threads(c, acct, tids, SIZE_MAX, &huge) == JMAP_E_MISUSE);
  jmap_threads_free(ths);

  /* Identities: what a sender enumerates before jmap_send. */
  jmap_identities *ids = NULL;
  assert(jmap_get_identities(c, acct, &ids) == JMAP_OK);
  assert(jmap_identities_count(ids) >= 1);
  const jmap_identity *ident = jmap_identities_at(ids, 0);
  assert(ident != NULL);
  /* SIZE_MAX must not narrow into range: still NULL, never a crash. */
  assert(jmap_identities_at(ids, SIZE_MAX) == NULL);
  assert(jmap_identity_id(ident) != NULL);
  assert(jmap_identity_email(ident) != NULL);
  assert(jmap_identity_name(ident) != NULL);
  jmap_identities_free(ids);

  /* Vacation: the singleton's current settings. */
  jmap_vacation *v = NULL;
  assert(jmap_get_vacation(c, acct, &v) == JMAP_OK);
  assert(jmap_vacation_is_enabled(v) == 1);
  assert(jmap_vacation_subject(v) != NULL);
  assert(jmap_vacation_text_body(v) != NULL);
  jmap_vacation_free(v);
  jmap_vacation_free(NULL);

  /* RFC 8621 §8.1 guarantees exactly one VacationResponse record. A
   * server that returns two must be rejected as JMAP_E_PROTOCOL, not
   * read via "first entry wins" or "last entry wins": either would let
   * a caller-visible field silently pair values across records that
   * never coexisted on the wire. */
  jmap_vacation *bad = NULL;
  assert(jmap_get_vacation(c, acct, &bad) == JMAP_E_PROTOCOL);
  assert(bad == NULL);
  assert(strlen(jmap_errmsg(c)) > 0);

  jmap_client_free(c);
  free(st.last_request); free(st.last_url);
  jmap_cleanup();
  printf("t13 ok\n");
  return 0;
}
