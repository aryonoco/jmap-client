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
  const char *bodies[] = { SESSION_JSON, SET_UPDATED_JSON, SET_MIXED_JSON };
  canned_state st = { bodies, 3, 0, NULL, NULL, 0 };
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
  assert(strstr(st.last_request, "keywords/$seen") != NULL);
  jmap_set_result_free(r);

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
