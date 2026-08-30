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
static const char *EMAIL_GET_JSON =
    "{\"methodResponses\":[[\"Email/"
    "get\",{\"accountId\":\"A1\",\"state\":\"es1\",\"list\":[{\"id\":\"em-1\","
    "\"threadId\":\"th-1\",\"from\":[{\"name\":\"Alice\",\"email\":\"alice@"
    "example.com\"}],\"subject\":\"Re: phase-l 7 "
    "delta\",\"receivedAt\":\"2026-05-05T11:18:46Z\",\"hasAttachment\":false,"
    "\"preview\":\"hello preview "
    "text\",\"textBody\":[{\"partId\":\"1\",\"blobId\":\"b1\",\"size\":26,"
    "\"name\":null,\"type\":\"text/"
    "plain\",\"charset\":\"utf-8\",\"disposition\":null,\"cid\":null,"
    "\"language\":null,\"location\":null}],\"bodyValues\":{\"1\":{"
    "\"isEncodingProblem\":false,\"isTruncated\":false,\"value\":\"decoded "
    "text "
    "body\"}}},{\"id\":\"em-2\"}],\"notFound\":[\"em-gone\"]},\"c0\"]],"
    "\"sessionState\":\"s1\"}";

int main(void) {
  assert(jmap_init() == JMAP_OK);
  const char *bodies[] = {SESSION_JSON, EMAIL_GET_JSON};
  canned_state st = {bodies, 2, 0, NULL, NULL, 0};
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c) ==
         JMAP_OK);
  jmap_transport_free(t);
  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  const char *ids[] = {"em-1", "em-2", "em-gone"};
  jmap_emails *es = NULL;
  assert(jmap_get_emails(c, acct, ids, 3, &es) == JMAP_OK);
  assert(jmap_emails_count(es) == 2);
  assert(jmap_emails_notfound_count(es) == 1);
  assert(jmap_emails_notfound_at(es, 0) != NULL);
  assert(jmap_emails_notfound_at(es, 1) == NULL);

  /* The emitted request carried exactly the ids we passed. */
  assert(strstr(st.last_request, "em-gone") != NULL);

  const jmap_email *full = NULL, *sparse = NULL;
  for (size_t i = 0; i < jmap_emails_count(es); i++) {
    const jmap_email *e = jmap_emails_at(es, i);
    assert(e != NULL && jmap_email_id(e) != NULL);
    if (jmap_email_subject(e) != NULL)
      full = e;
    else
      sparse = e;
  }
  assert(full != NULL && sparse != NULL);

  /* Present fields are borrows; absent Opt fields are NULL. */
  assert(strlen(jmap_email_subject(full)) > 0);
  assert(jmap_email_from_email(full) != NULL);
  assert(jmap_email_preview(full) != NULL);
  assert(jmap_email_text_body(full) != NULL);
  assert(jmap_email_has_attachment(full) == 0);
  assert(jmap_email_from_email(sparse) == NULL);
  assert(jmap_email_from_name(sparse) == NULL);

  /* Out of range is NULL, never a crash. SIZE_MAX exercises the
   * unsigned-domain bounds check directly: narrowing to int first
   * would raise a RangeDefect across this raises:[] boundary. */
  assert(jmap_emails_at(es, 99) == NULL);
  assert(jmap_emails_at(es, SIZE_MAX) == NULL);
  assert(jmap_emails_notfound_at(es, SIZE_MAX) == NULL);

  /* A NULL ids array with a nonzero count is misuse. */
  jmap_emails *bad = NULL;
  assert(jmap_get_emails(c, acct, NULL, 1, &bad) == JMAP_E_MISUSE);

  /* A count too large to narrow to Nim's signed int is misuse, not a
   * RangeDefect abort: SIZE_MAX exercises parseIdArray's unsigned-domain
   * bound on n itself, before the loop ever narrows it or touches ids. */
  jmap_emails *huge = NULL;
  assert(jmap_get_emails(c, acct, ids, SIZE_MAX, &huge) == JMAP_E_MISUSE);

  jmap_emails_free(es);
  jmap_emails_free(NULL);
  jmap_client_free(c);
  free(st.last_request);
  free(st.last_url);
  jmap_cleanup();
  printf("t07 ok\n");
  return 0;
}
