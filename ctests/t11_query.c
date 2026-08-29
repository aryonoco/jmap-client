/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";
/* Generated via a throwaway nim r script that built the query and get
 * argument objects as JsonNode, round-tripped each through the real
 * QueryResponse[Email].fromJson / GetResponse[Email].fromJson, then
 * wrapped both in a methodResponses envelope with the call ids ("c0",
 * "c1") the library's own builder assigns in invocation order. The
 * Email/get record reuses the em-1 shape from t07_emails.c, already
 * proven to decode. */
static const char *QUERY_JSON = "{\"methodResponses\":[[\"Email/query\",{\"accountId\":\"A1\",\"queryState\":\"qs1\",\"canCalculateChanges\":false,\"position\":0,\"ids\":[\"em-1\"]},\"c0\"],[\"Email/get\",{\"accountId\":\"A1\",\"state\":\"es1\",\"list\":[{\"id\":\"em-1\",\"threadId\":\"th-1\",\"from\":[{\"name\":\"Alice\",\"email\":\"alice@example.com\"}],\"subject\":\"Re: phase-l 7 delta\",\"receivedAt\":\"2026-05-05T11:18:46Z\",\"hasAttachment\":false,\"preview\":\"hello preview text\",\"textBody\":[{\"partId\":\"1\",\"blobId\":\"b1\",\"size\":26,\"name\":null,\"type\":\"text/plain\",\"charset\":\"utf-8\",\"disposition\":null,\"cid\":null,\"language\":null,\"location\":null}],\"bodyValues\":{\"1\":{\"isEncodingProblem\":false,\"isTruncated\":false,\"value\":\"decoded text body\"}}}],\"notFound\":[]},\"c1\"]],\"sessionState\":\"s1\"}";

int main(void) {
  assert(jmap_init() == JMAP_OK);

  jmap_query *q = NULL;
  assert(jmap_query_new(&q) == JMAP_OK);
  assert(jmap_query_set_str(q, JMAP_Q_IN_MAILBOX, "mb-1") == JMAP_OK);
  assert(jmap_query_set_str(q, JMAP_Q_TEXT, "invoice") == JMAP_OK);
  assert(jmap_query_set_u32(q, JMAP_Q_LIMIT, 10) == JMAP_OK);
  assert(jmap_query_set_u32(q, JMAP_Q_READ_STATE, JMAP_READ_UNREAD)
         == JMAP_OK);
  assert(jmap_query_set_u32(q, JMAP_Q_SORT, JMAP_SORT_RECEIVED_AT_DESC)
         == JMAP_OK);

  /* Wrong-type setter for the option is misuse; so are bad ordinals. */
  assert(jmap_query_set_u32(q, JMAP_Q_IN_MAILBOX, 3) == JMAP_E_MISUSE);
  assert(jmap_query_set_str(q, JMAP_Q_LIMIT, "10") == JMAP_E_MISUSE);
  assert(jmap_query_set_u32(q, JMAP_Q_READ_STATE, 99) == JMAP_E_MISUSE);
  assert(jmap_query_set_str(q, JMAP_Q_TEXT, NULL) == JMAP_E_MISUSE);

  /* A value that cannot be parsed is refused at the setter, on the
   * validation rail — the spec is parsed once, here, not at the call. */
  assert(jmap_query_set_str(q, JMAP_Q_IN_MAILBOX, "") == JMAP_E_VALIDATION);

  const char *bodies[] = { SESSION_JSON, QUERY_JSON };
  canned_state st = { bodies, 2, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);
  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  jmap_emails *es = NULL;
  assert(jmap_query_emails(c, acct, q, &es) == JMAP_OK);
  assert(jmap_emails_count(es) >= 1);

  /* The lowering reached the wire: mailbox filter, unread as a $seen
   * notKeyword, the text needle, the limit, and the sort property. */
  assert(strstr(st.last_request, "mb-1") != NULL);
  assert(strstr(st.last_request, "notKeyword") != NULL);
  assert(strstr(st.last_request, "$seen") != NULL);
  assert(strstr(st.last_request, "invoice") != NULL);
  assert(strstr(st.last_request, "\"limit\":10") != NULL);
  assert(strstr(st.last_request, "receivedAt") != NULL);

  /* NULL query = no filter, no sort, no limit — still a valid call. */
  const char *bodies2[] = { QUERY_JSON };
  st.bodies = bodies2; st.count = 1; st.next = 0;
  jmap_emails *all = NULL;
  assert(jmap_query_emails(c, acct, NULL, &all) == JMAP_OK);
  assert(strstr(st.last_request, "notKeyword") == NULL);

  /* Read state is one ordinal choosing between two keyword slots, not
   * two independently-set slots: replacing UNREAD with READ must drop
   * the stale notKeyword, not merely add hasKeyword alongside it. */
  jmap_query *q2 = NULL;
  assert(jmap_query_new(&q2) == JMAP_OK);
  assert(jmap_query_set_u32(q2, JMAP_Q_READ_STATE, JMAP_READ_UNREAD)
         == JMAP_OK);
  assert(jmap_query_set_u32(q2, JMAP_Q_READ_STATE, JMAP_READ_READ)
         == JMAP_OK);
  const char *bodies3[] = { QUERY_JSON };
  st.bodies = bodies3; st.count = 1; st.next = 0;
  jmap_emails *readOnly = NULL;
  assert(jmap_query_emails(c, acct, q2, &readOnly) == JMAP_OK);
  assert(strstr(st.last_request, "\"hasKeyword\":\"$seen\"") != NULL);
  assert(strstr(st.last_request, "notKeyword") == NULL);
  jmap_emails_free(readOnly);
  jmap_query_free(q2);

  jmap_emails_free(es);
  jmap_emails_free(all);
  jmap_query_free(q);
  jmap_query_free(NULL);
  jmap_client_free(c);
  free(st.last_request); free(st.last_url);
  jmap_cleanup();
  printf("t11 ok\n");
  return 0;
}
