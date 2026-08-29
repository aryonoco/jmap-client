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
 * through fromJson before these literals were pasted in. */
static const char *VACATION_SET_JSON = "{\"methodResponses\":[[\"VacationResponse/set\",{\"accountId\":\"A1\",\"oldState\":\"s1\",\"newState\":\"s2\",\"updated\":{\"singleton\":null}},\"c0\"]],\"sessionState\":\"s1\"}";
static const char *VACATION_SET_REFUSED_JSON = "{\"methodResponses\":[[\"VacationResponse/set\",{\"accountId\":\"A1\",\"oldState\":\"s1\",\"newState\":\"s2\",\"notUpdated\":{\"singleton\":{\"type\":\"invalidProperties\",\"properties\":[\"textBody\"]}}},\"c0\"]],\"sessionState\":\"s1\"}";

int main(void) {
  assert(jmap_init() == JMAP_OK);
  const char *bodies[] = { SESSION_JSON, VACATION_SET_JSON,
                           VACATION_SET_JSON, VACATION_SET_JSON,
                           VACATION_SET_REFUSED_JSON };
  canned_state st = { bodies, 5, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);
  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  /* Three properties, three fates on the wire: a value, an explicit
   * clear, and — for the property no setter names — nothing at all. */
  jmap_vacation_update *u = NULL;
  assert(jmap_vacation_update_new(&u) == JMAP_OK);
  assert(jmap_vacation_update_set_enabled(u, JMAP_VACATION_ENABLED)
         == JMAP_OK);
  assert(jmap_vacation_update_set_subject(u, "Out of office") == JMAP_OK);
  assert(jmap_vacation_update_set_text_body(u, NULL) == JMAP_OK);
  jmap_set_result *r = NULL;
  assert(jmap_set_vacation(c, acct, u, &r) == JMAP_OK);
  assert(strstr(st.last_request, "\"isEnabled\":true") != NULL);
  assert(strstr(st.last_request, "\"subject\":\"Out of office\"") != NULL);
  assert(strstr(st.last_request, "\"textBody\":null") != NULL);
  assert(jmap_set_result_updated_count(r) == 1);
  assert(strcmp(jmap_set_result_updated_at(r, 0), "singleton") == 0);
  assert(jmap_set_result_failure_count(r) == 0);
  /* A singleton update submits no create or destroy rows. */
  assert(jmap_set_result_destroyed_count(r) == 0);
  jmap_set_result_free(r);
  jmap_vacation_update_free(u);

  /* A fresh update naming one property sends ONLY that property: the
   * other two are absent from the patch, not present-and-null. */
  jmap_vacation_update *only = NULL;
  assert(jmap_vacation_update_new(&only) == JMAP_OK);
  assert(jmap_vacation_update_set_enabled(only, JMAP_VACATION_DISABLED)
         == JMAP_OK);
  jmap_set_result *r2 = NULL;
  assert(jmap_set_vacation(c, acct, only, &r2) == JMAP_OK);
  assert(strstr(st.last_request, "\"isEnabled\":false") != NULL);
  assert(strstr(st.last_request, "subject") == NULL);
  assert(strstr(st.last_request, "textBody") == NULL);
  jmap_set_result_free(r2);
  jmap_vacation_update_free(only);

  /* Calling a setter twice replaces the earlier value: the wire
   * carries only the final call, never both. */
  jmap_vacation_update *twice = NULL;
  assert(jmap_vacation_update_new(&twice) == JMAP_OK);
  assert(jmap_vacation_update_set_subject(twice, "First") == JMAP_OK);
  assert(jmap_vacation_update_set_subject(twice, "Second") == JMAP_OK);
  jmap_set_result *rTwice = NULL;
  assert(jmap_set_vacation(c, acct, twice, &rTwice) == JMAP_OK);
  assert(strstr(st.last_request, "\"subject\":\"Second\"") != NULL);
  assert(strstr(st.last_request, "First") == NULL);
  jmap_set_result_free(rTwice);
  jmap_vacation_update_free(twice);

  /* A server refusal is DATA: the call completed, so the status is
   * JMAP_OK, the updated list is EMPTY, and the wire error type
   * crosses intact. A caller that read JMAP_OK as "there is an updated
   * row" would dereference NULL here. */
  jmap_vacation_update *refused = NULL;
  assert(jmap_vacation_update_new(&refused) == JMAP_OK);
  assert(jmap_vacation_update_set_subject(refused, "Third") == JMAP_OK);
  jmap_set_result *r3 = NULL;
  assert(jmap_set_vacation(c, acct, refused, &r3) == JMAP_OK);
  assert(jmap_set_result_updated_count(r3) == 0);
  assert(jmap_set_result_updated_at(r3, 0) == NULL);
  assert(jmap_set_result_failure_count(r3) == 1);
  assert(strcmp(jmap_set_result_failure_id_at(r3, 0), "singleton") == 0);
  assert(strcmp(jmap_set_result_failure_type_at(r3, 0),
                "invalidProperties") == 0);
  jmap_set_result_free(r3);
  jmap_vacation_update_free(refused);

  /* Nothing below may reach the transport: the request log must still
   * end with the refused call's "Third" subject and no further canned
   * response may be consumed. */
  const int served = st.next;
  /* Never dereferenced — only compared, to prove an out-parameter was
   * left alone. */
  jmap_set_result *sentinel = (jmap_set_result *)&st;

  /* An update no setter touched is refused before the wire, and the
   * diagnosis names the C-level fault. */
  jmap_vacation_update *empty = NULL;
  assert(jmap_vacation_update_new(&empty) == JMAP_OK);
  jmap_set_result *re = sentinel;
  assert(jmap_set_vacation(c, acct, empty, &re) == JMAP_E_VALIDATION);
  assert(re == sentinel);
  assert(strstr(jmap_errmsg(c), "no properties") != NULL);
  jmap_vacation_update_free(empty);

  jmap_set_result *rn = sentinel;
  assert(jmap_set_vacation(c, acct, NULL, &rn) == JMAP_E_MISUSE);
  assert(rn == sentinel);

  jmap_vacation_update *mis = NULL;
  assert(jmap_vacation_update_new(&mis) == JMAP_OK);
  assert(jmap_set_vacation(c, acct, mis, NULL) == JMAP_E_MISUSE);
  assert(jmap_vacation_update_set_enabled(mis, (jmap_vacation_state)7)
         == JMAP_E_MISUSE);
  jmap_vacation_update_free(mis);

  assert(jmap_vacation_update_new(NULL) == JMAP_E_MISUSE);
  assert(jmap_vacation_update_set_enabled(NULL, JMAP_VACATION_ENABLED)
         == JMAP_E_MISUSE);
  assert(jmap_vacation_update_set_subject(NULL, "x") == JMAP_E_MISUSE);
  assert(jmap_vacation_update_set_text_body(NULL, NULL) == JMAP_E_MISUSE);
  jmap_vacation_update_free(NULL);

  assert(st.next == served);
  assert(strstr(st.last_request, "Third") != NULL);

  jmap_client_free(c);
  free(st.last_request); free(st.last_url);
  jmap_cleanup();
  printf("t09 ok\n");
  return 0;
}
