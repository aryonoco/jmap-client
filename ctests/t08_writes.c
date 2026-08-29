/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";
static const char *SET_UPDATED_JSON = "{\"methodResponses\":[[\"Email/set\",{\"accountId\":\"A1\",\"oldState\":\"s1\",\"newState\":\"s2\",\"updated\":{\"em-1\":null}},\"c0\"]],\"sessionState\":\"s1\"}";
static const char *SET_MIXED_JSON = "{\"methodResponses\":[[\"Email/set\",{\"accountId\":\"A1\",\"oldState\":\"s1\",\"newState\":\"s2\",\"destroyed\":[\"em-1\"],\"notDestroyed\":{\"em-2\":{\"type\":\"forbidden\"}}},\"c0\"]],\"sessionState\":\"s1\"}";

int main(void) {
  assert(jmap_init() == JMAP_OK);
  /* mark_read, mark_unread and move_emails each drive one Email/set
   * exchange whose "updated" shape SET_UPDATED_JSON already satisfies
   * (its content does not depend on which patch produced it); destroy
   * gets its own partial-success fixture. */
  const char *bodies[] = {
    SESSION_JSON, SET_UPDATED_JSON, SET_UPDATED_JSON, SET_UPDATED_JSON,
    SET_MIXED_JSON
  };
  canned_state st = { bodies, 5, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);
  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  /* Mark read: one updated id, no failures, and the wire carried the
   * $seen keyword patch. */
  const char *ids[] = { "em-1" };
  jmap_set_result *r = NULL;
  assert(jmap_mark_read(c, acct, ids, 1, &r) == JMAP_OK);
  assert(jmap_set_result_updated_count(r) == 1);
  assert(strcmp(jmap_set_result_updated_at(r, 0), "em-1") == 0);
  /* SIZE_MAX must not narrow into range: still NULL, never a crash. */
  assert(jmap_set_result_updated_at(r, SIZE_MAX) == NULL);
  assert(jmap_set_result_failure_count(r) == 0);
  assert(strstr(st.last_request, "\"keywords/$seen\":true") != NULL);
  jmap_set_result_free(r);

  /* A count too large to narrow to Nim's signed int is misuse, not a
   * RangeDefect abort: SIZE_MAX exercises parseIdArray's unsigned-domain
   * bound on n itself, before the loop ever narrows it or touches ids —
   * the same guard t07/t13 already pin via other callers, exercised
   * here too so a future change to this call site cannot silently
   * unpin it. */
  jmap_set_result *readHuge = NULL;
  assert(jmap_mark_read(c, acct, ids, SIZE_MAX, &readHuge) == JMAP_E_MISUSE);

  /* Mark unread: same shape, opposite patch value (keyword removal). */
  jmap_set_result *u = NULL;
  assert(jmap_mark_unread(c, acct, ids, 1, &u) == JMAP_OK);
  assert(jmap_set_result_updated_count(u) == 1);
  assert(strcmp(jmap_set_result_updated_at(u, 0), "em-1") == 0);
  assert(strstr(st.last_request, "\"keywords/$seen\":null") != NULL);
  jmap_set_result_free(u);

  jmap_set_result *unreadHuge = NULL;
  assert(jmap_mark_unread(c, acct, ids, SIZE_MAX, &unreadHuge)
         == JMAP_E_MISUSE);

  /* Move: a full mailbox-membership replace naming only the
   * destination, and its own mailbox_id argument has its own checks. */
  jmap_set_result *m = NULL;
  assert(jmap_move_emails(c, acct, ids, 1, "mb-1", &m) == JMAP_OK);
  assert(jmap_set_result_updated_count(m) == 1);
  assert(strstr(st.last_request, "\"mailboxIds\":{\"mb-1\":true}") != NULL);
  jmap_set_result_free(m);

  jmap_set_result *moveHuge = NULL;
  assert(jmap_move_emails(c, acct, ids, SIZE_MAX, "mb-1", &moveHuge)
         == JMAP_E_MISUSE);

  /* A NULL mailbox_id is misuse, checked before any id parsing or
   * network traffic. */
  jmap_set_result *moveNoMailbox = NULL;
  assert(jmap_move_emails(c, acct, ids, 1, NULL, &moveNoMailbox)
         == JMAP_E_MISUSE);

  /* An invalid mailbox_id (empty string fails parseIdFromServer's
   * 1-255 octet minimum) is a validation failure, also caught before
   * any network traffic. */
  jmap_set_result *moveBadMailbox = NULL;
  assert(jmap_move_emails(c, acct, ids, 1, "", &moveBadMailbox)
         == JMAP_E_VALIDATION);

  /* Destroy: partition surfaces both halves as data. */
  const char *dids[] = { "em-1", "em-2" };
  jmap_set_result *d = NULL;
  assert(jmap_destroy_emails(c, acct, dids, 2, &d) == JMAP_OK);
  assert(jmap_set_result_destroyed_count(d) == 1);
  assert(strcmp(jmap_set_result_destroyed_at(d, 0), "em-1") == 0);
  /* SIZE_MAX must not narrow into range: still NULL, never a crash. */
  assert(jmap_set_result_destroyed_at(d, SIZE_MAX) == NULL);
  assert(jmap_set_result_failure_count(d) == 1);
  assert(strcmp(jmap_set_result_failure_id_at(d, 0), "em-2") == 0);
  assert(strcmp(jmap_set_result_failure_type_at(d, 0), "forbidden") == 0);
  assert(jmap_set_result_failure_id_at(d, 1) == NULL);
  assert(jmap_set_result_failure_id_at(d, SIZE_MAX) == NULL);
  assert(jmap_set_result_failure_type_at(d, SIZE_MAX) == NULL);
  jmap_set_result_free(d);

  jmap_set_result *destroyHuge = NULL;
  assert(jmap_destroy_emails(c, acct, dids, SIZE_MAX, &destroyHuge)
         == JMAP_E_MISUSE);

  /* Empty ids on the update rail rejects at the seal: no request. */
  jmap_set_result *e = NULL;
  assert(jmap_mark_read(c, acct, NULL, 0, &e) == JMAP_E_VALIDATION);

  jmap_set_result_free(NULL);
  jmap_client_free(c);
  free(st.last_request); free(st.last_url);
  jmap_cleanup();
  printf("t08 ok\n");
  return 0;
}
