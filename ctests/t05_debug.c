/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";

typedef struct {
  int sends;
  int receives;
  size_t received_bytes;
  char received[4096]; /* copy of the receive fire's payload, NUL-terminated here for strcmp */
} dbg;

static void on_wire(void *userdata, jmap_wire_direction d,
                    const uint8_t *bytes, size_t len) {
  dbg *g = (dbg *)userdata;
  /* Every fire, including a zero-length one, hands back a live
   * pointer — never NULL, so memcpy(dst, bytes, len) is always safe
   * even at len == 0. */
  assert(bytes != NULL);
  if (d == JMAP_WIRE_SEND) {
    g->sends++;
    /* The session GET carries no request body. */
    assert(len == 0);
  } else {
    g->receives++;
    g->received_bytes += len;
    assert(len < sizeof(g->received));
    memcpy(g->received, bytes, len);
    g->received[len] = '\0';
  }
}

int main(void) {
  assert(jmap_init() == JMAP_OK);
  const char *bodies[] = { SESSION_JSON };
  canned_state st = { bodies, 1, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);

  dbg g;
  memset(&g, 0, sizeof(g));
  assert(jmap_set_debug_callback(c, on_wire, &g) == JMAP_OK);

  const char *primary = NULL;
  assert(jmap_client_primary_account(c, &primary) == JMAP_OK);
  /* One HTTP exchange (the session GET) = one send + one receive. */
  assert(g.sends == 1 && g.receives == 1);
  assert(g.received_bytes == strlen(SESSION_JSON));
  /* The receive fire's payload is the session body itself, not just
   * the right length. */
  assert(strcmp(g.received, SESSION_JSON) == 0);

  /* Detach: NULL fn stops the stream (no exchange happens on a cached
   * accessor anyway, so pin only that detaching is accepted). */
  assert(jmap_set_debug_callback(c, NULL, NULL) == JMAP_OK);
  assert(jmap_set_debug_callback(NULL, on_wire, &g) == JMAP_E_MISUSE);

  jmap_client_free(c);
  free(st.last_request); free(st.last_url);
  jmap_cleanup();
  printf("t05 ok\n");
  return 0;
}
