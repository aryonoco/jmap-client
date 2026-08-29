/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";
/* Generated via a throwaway nim r script that built the real
 * SetResponse[NoCreate, PartialVacationResponse] value, serialised it
 * with the library's own toJson, and round-tripped the result back
 * through fromJson before this literal was pasted in. */
static const char *VACATION_SET_JSON = "{\"methodResponses\":[[\"VacationResponse/set\",{\"accountId\":\"A1\",\"oldState\":\"s1\",\"newState\":\"s2\",\"updated\":{\"singleton\":null}},\"c0\"]],\"sessionState\":\"s1\"}";

int main(void) {
  assert(jmap_init() == JMAP_OK);
  const char *bodies[] = { SESSION_JSON, VACATION_SET_JSON };
  canned_state st = { bodies, 2, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);
  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  jmap_set_result *r = NULL;
  assert(jmap_set_vacation(c, acct, JMAP_VACATION_ENABLED,
                           "Out of office", "Back Monday.", &r) == JMAP_OK);
  assert(jmap_set_result_updated_count(r) == 1);
  assert(strcmp(jmap_set_result_updated_at(r, 0), "singleton") == 0);
  assert(strstr(st.last_request, "isEnabled") != NULL);
  assert(strstr(st.last_request, "Out of office") != NULL);
  jmap_set_result_free(r);

  /* NULL subject/body mean "leave unset": only isEnabled travels. */
  const char *bodies2[] = { VACATION_SET_JSON };
  st.bodies = bodies2; st.count = 1; st.next = 0;
  jmap_set_result *r2 = NULL;
  assert(jmap_set_vacation(c, acct, JMAP_VACATION_DISABLED,
                           NULL, NULL, &r2) == JMAP_OK);
  assert(strstr(st.last_request, "subject") == NULL);
  jmap_set_result_free(r2);

  /* An out-of-range state ordinal is misuse. */
  jmap_set_result *r3 = NULL;
  assert(jmap_set_vacation(c, acct, (jmap_vacation_state)7,
                           NULL, NULL, &r3) == JMAP_E_MISUSE);

  jmap_client_free(c);
  free(st.last_request); free(st.last_url);
  jmap_cleanup();
  printf("t09 ok\n");
  return 0;
}
