/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";

/* RFC 8620 section 3.6.1: the server rejects the whole request rather
 * than any method in it, and says so with an RFC 7807 problem details
 * object. Taken from that section's second example. */
static const char *LIMIT_PROBLEM = "{\"type\":\"urn:ietf:params:jmap:error:limit\",\"limit\":\"maxSizeRequest\",\"status\":400,\"detail\":\"The request is larger than the server is willing to process.\"}";

/* The same class of rejection from a server that answers it with a 200
 * instead of the HTTP error status section 3.6.1 asks for. It offers
 * neither a title nor a detail, so the type URI is all the diagnostic
 * can be built from -- which is what makes it visible in jmap_errmsg()
 * below. */
static const char *BARE_PROBLEM = "{\"type\":\"urn:ietf:params:jmap:error:notRequest\",\"status\":400}";

int main(void) {
  assert(jmap_init() == JMAP_OK);

  /* The rejection as a server sends it: an HTTP error status carrying
   * problem details, which the library classifies by status and
   * Content-Type before it reads the body. */
  const canned_reply replies[] = {
    { .body = SESSION_JSON },
    { .body = LIMIT_PROBLEM, .http_status = 400,
      .content_type = "application/problem+json" },
  };
  canned_reply_state st = { replies, 2, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_reply_make_transport(&st);
  assert(t != NULL);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);

  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  /* A 4xx whose body does not parse as problem details is
   * JMAP_E_TRANSPORT, so this status is what says the details were
   * read rather than merely the status line. */
  jmap_mailboxes *mbs = NULL;
  assert(jmap_get_mailboxes(c, acct, &mbs) == JMAP_E_REQUEST);
  assert(mbs == NULL); /* nothing handed back, so nothing to free */
  /* The rejected exchange was the API call and not the session fetch:
   * both scripted replies went out, and the last request carried the
   * method. */
  assert(st.next == 2);
  assert(st.last_request != NULL);
  assert(strstr(st.last_request, "Mailbox/get") != NULL);
  const char *msg = jmap_errmsg(c);
  assert(msg != NULL);
  assert(strcmp(msg, "no error") != 0);
  /* The server's own words reach C, rather than a status name. */
  assert(strstr(msg, "willing to process") != NULL);
  /* JMAP_E_REQUEST is neither of the two typed-error statuses
   * jmap_errtype() answers for, so the answer is NULL. */
  assert(jmap_errtype(c) == NULL);

  jmap_client_free(c);
  assert(st.closes == 1);
  free(st.last_request);
  free(st.last_url);

  /* The same rejection arriving on a 200. A body carrying problem
   * details and no method responses is read as the rejection it is, so
   * a server that answered with the wrong status still reaches C as
   * JMAP_E_REQUEST rather than as a malformed response. */
  const canned_reply replies2[] = {
    { .body = SESSION_JSON },
    { .body = BARE_PROBLEM },
  };
  canned_reply_state st2 = { replies2, 2, 0, NULL, NULL, 0 };
  jmap_transport *t2 = canned_reply_make_transport(&st2);
  assert(t2 != NULL);
  jmap_client *c2 = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t2, &c2)
         == JMAP_OK);
  jmap_transport_free(t2);

  const char *acct2 = NULL;
  assert(jmap_client_primary_account(c2, &acct2) == JMAP_OK);

  jmap_mailboxes *mbs2 = NULL;
  assert(jmap_get_mailboxes(c2, acct2, &mbs2) == JMAP_E_REQUEST);
  assert(mbs2 == NULL);
  assert(st2.next == 2);
  assert(st2.last_request != NULL);
  assert(strstr(st2.last_request, "Mailbox/get") != NULL);
  const char *msg2 = jmap_errmsg(c2);
  assert(msg2 != NULL);
  assert(strcmp(msg2, "no error") != 0);
  /* With no title and no detail to draw on, the type URI itself is the
   * diagnostic, so it survives the trip to C unaltered. */
  assert(strstr(msg2, "urn:ietf:params:jmap:error:notRequest") != NULL);
  assert(jmap_errtype(c2) == NULL);

  jmap_client_free(c2);
  assert(st2.closes == 1);
  free(st2.last_request);
  free(st2.last_url);

  jmap_cleanup();
  printf("t14 ok\n");
  return 0;
}
