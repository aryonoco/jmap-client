/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";

int main(void) {
  assert(jmap_init() == JMAP_OK);

  /* NULL send callback is misuse. */
  jmap_transport *bad = NULL;
  assert(jmap_transport_new(NULL, canned_close, NULL, &bad) == JMAP_E_MISUSE);

  /* Full lifecycle: attach, use, free both, close fires exactly once. */
  const char *bodies[] = { SESSION_JSON };
  canned_state st = { bodies, 1, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  assert(t != NULL);

  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);

  /* Attaching the same transport to a second client is misuse. */
  jmap_client *c2 = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c2)
         == JMAP_E_MISUSE);
  assert(c2 == NULL);

  /* The consumer may free its own transport handle immediately after
   * attach; the client's reference keeps it alive. */
  jmap_transport_free(t);
  assert(st.closes == 0);

  /* No accessor exists yet to force an exchange; the close-once and
   * attach-once contracts are what this test pins. */

  jmap_client_free(c);
  assert(st.closes == 1); /* last ref dropped -> close fired once */

  free(st.last_request);
  free(st.last_url);
  jmap_cleanup();
  printf("t03 ok\n");
  return 0;
}
