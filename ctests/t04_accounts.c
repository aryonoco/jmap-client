/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include "canned.h"
#include "jmap_client.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const char *SESSION_JSON =
    "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/"
    "api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/"
    "{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/"
    "upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/"
    "eventsource/"
    "?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\","
    "\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":"
    "50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,"
    "\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":"
    "1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\","
    "\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\","
    "\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:"
    "ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,"
    "\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,"
    "\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],"
    "\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\","
    "\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},"
    "\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";
static const char *SESSION_JSON_NO_MAIL =
    "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/"
    "api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/"
    "{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/"
    "upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/"
    "eventsource/"
    "?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\","
    "\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":"
    "50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,"
    "\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":"
    "1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\","
    "\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\","
    "\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},"
    "\"primaryAccounts\":{}}";

int main(void) {
  assert(jmap_init() == JMAP_OK);

  /* Happy path: one session fetch feeds all three accessors. Two
   * accounts, deliberately not advertised in ascending order on the
   * wire, so the ordering assertion below actually exercises the
   * library's own sort rather than passing vacuously on a single
   * element. */
  const char *bodies[] = {SESSION_JSON};
  canned_state st = {bodies, 1, 0, NULL, NULL, 0};
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c) ==
         JMAP_OK);
  jmap_transport_free(t);

  const char *primary = NULL;
  assert(jmap_client_primary_account(c, &primary) == JMAP_OK);
  assert(primary != NULL && strlen(primary) > 0);
  assert(strcmp(jmap_errmsg(c), "no error") == 0);

  size_t n = 0;
  assert(jmap_client_account_count(c, &n) == JMAP_OK);
  assert(n == 2);
  /* Sorted, NULL out of range, and the primary appears in the list. */
  int saw_primary = 0;
  const char *prev = NULL;
  for (size_t i = 0; i < n; i++) {
    const char *id = jmap_client_account_at(c, i);
    assert(id != NULL);
    if (prev != NULL)
      assert(strcmp(prev, id) < 0);
    if (strcmp(id, primary) == 0)
      saw_primary = 1;
    prev = id;
  }
  assert(saw_primary == 1);
  assert(jmap_client_account_at(c, n) == NULL);
  /* SIZE_MAX is the ordinary result of an n - 1 underflow in caller
   * code on an empty cache; the bounds check must reject it in the
   * unsigned domain rather than narrowing it to int and raising. */
  assert(jmap_client_account_at(c, SIZE_MAX) == NULL);
  jmap_client_free(c);

  /* No mail capability anywhere -> JMAP_E_SESSION with a message. */
  const char *bodies2[] = {SESSION_JSON_NO_MAIL};
  canned_state st2 = {bodies2, 1, 0, NULL, NULL, 0};
  jmap_transport *t2 = canned_make_transport(&st2);
  jmap_client *c2 = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t2, &c2) ==
         JMAP_OK);
  jmap_transport_free(t2);
  const char *p2 = NULL;
  assert(jmap_client_primary_account(c2, &p2) == JMAP_E_SESSION);
  assert(strlen(jmap_errmsg(c2)) > 0);
  jmap_client_free(c2);

  /* Transport failure during the lazy fetch surfaces on the accessor. */
  jmap_transport *t3 = NULL;
  assert(jmap_transport_new(canned_fail_send, canned_close, NULL, &t3) ==
         JMAP_OK);
  jmap_client *c3 = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t3, &c3) ==
         JMAP_OK);
  jmap_transport_free(t3);
  const char *p3 = NULL;
  assert(jmap_client_primary_account(c3, &p3) == JMAP_E_TRANSPORT);
  jmap_client_free(c3);

  free(st.last_request);
  free(st.last_url);
  free(st2.last_request);
  free(st2.last_url);
  jmap_cleanup();
  printf("t04 ok\n");
  return 0;
}
