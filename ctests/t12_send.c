/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";
/* Generated: built as three JsonNode method-response entries (Email/set
 * c0 creating the draft, EmailSubmission/set c1 creating the submission,
 * and the implicit Email/set c1 the server MUST emit after it per RFC
 * 8621 §7.5), round-tripped through the real sendPlainText one-shot
 * (which itself decodes via the SetResponse[Email] / SetResponse[
 * EmailSubmission] decoders) against the account SESSION_JSON names,
 * then echoed as this literal. */
static const char *SEND_JSON = "{\"methodResponses\":[[\"Email/set\",{\"accountId\":\"A1\",\"newState\":\"s2\",\"created\":{\"draft\":{\"id\":\"em-1\",\"blobId\":\"b1\",\"threadId\":\"th-1\",\"size\":42}}},\"c0\"],[\"EmailSubmission/set\",{\"accountId\":\"A1\",\"newState\":\"s3\",\"created\":{\"sub\":{\"id\":\"sub-1\"}}},\"c1\"],[\"Email/set\",{\"accountId\":\"A1\",\"newState\":\"s4\",\"updated\":{\"em-1\":null}},\"c1\"]],\"sessionState\":\"s1\"}";

/* True when the JSON key `key` is followed by `needle` before the
 * bracket that closes that key's address array. Every recipient also
 * appears in the submission envelope's rcptTo union, so a bare
 * presence check would pass a setter wired to the wrong role; this
 * binds an address to its own header without parsing JSON, and spans
 * the whole array rather than the first object, so a role carrying two
 * addresses answers for both. */
static int role_carries(const char *req, const char *key,
                        const char *needle) {
  const char *at = strstr(req, key);
  const char *end = at ? strchr(at, ']') : NULL;
  const char *hit = at ? strstr(at, needle) : NULL;
  return at != NULL && end != NULL && hit != NULL && hit < end;
}

int main(void) {
  /* Before jmap_init the runtime is not up, so an entry point that
   * allocates must refuse rather than run. */
  jmap_message *pre = NULL;
  assert(jmap_message_new(&pre) == JMAP_E_MISUSE);
  assert(pre == NULL);

  assert(jmap_init() == JMAP_OK);

  /* NULL out-parameter, NULL handle, NULL value: all misuse, all
   * detected before any dereference. */
  assert(jmap_message_new(NULL) == JMAP_E_MISUSE);
  assert(jmap_message_set_str(NULL, JMAP_MSG_TO, "a@example.com")
         == JMAP_E_MISUSE);
  assert(jmap_message_add_str(NULL, JMAP_MSG_TO, "a@example.com")
         == JMAP_E_MISUSE);

  jmap_message *m = NULL;
  assert(jmap_message_new(&m) == JMAP_OK);
  assert(m != NULL);
  assert(jmap_message_set_str(m, JMAP_MSG_TO, NULL) == JMAP_E_MISUSE);
  assert(jmap_message_add_str(m, JMAP_MSG_TO, NULL) == JMAP_E_MISUSE);
  /* An option this build does not know is refused by either verb,
   * never a no-op. Both rejected values are asserted ABSENT from the
   * wire below, so a refusal that quietly wrote somewhere fails. */
  assert(jmap_message_set_str(m, (jmap_message_opt)99, "rejected-ordinal")
         == JMAP_E_MISUSE);
  assert(jmap_message_add_str(m, (jmap_message_opt)99, "rejected-ordinal")
         == JMAP_E_MISUSE);
  /* Appending is defined only for a list-valued role; the other six
   * options hold one value each, and growing one has no meaning. */
  assert(jmap_message_add_str(m, JMAP_MSG_IDENTITY_ID, "rejected-append")
         == JMAP_E_MISUSE);
  assert(jmap_message_add_str(m, JMAP_MSG_DRAFTS_MAILBOX, "rejected-append")
         == JMAP_E_MISUSE);
  assert(jmap_message_add_str(m, JMAP_MSG_SENT_MAILBOX, "rejected-append")
         == JMAP_E_MISUSE);
  assert(jmap_message_add_str(m, JMAP_MSG_FROM, "rejected-append")
         == JMAP_E_MISUSE);
  assert(jmap_message_add_str(m, JMAP_MSG_SUBJECT, "rejected-append")
         == JMAP_E_MISUSE);
  assert(jmap_message_add_str(m, JMAP_MSG_BODY, "rejected-append")
         == JMAP_E_MISUSE);
  /* An id that is not an id is refused where the caller supplied it. */
  assert(jmap_message_set_str(m, JMAP_MSG_DRAFTS_MAILBOX, "")
         == JMAP_E_VALIDATION);

  assert(jmap_message_set_str(m, JMAP_MSG_IDENTITY_ID, "identity-1")
         == JMAP_OK);
  assert(jmap_message_set_str(m, JMAP_MSG_DRAFTS_MAILBOX, "mb-drafts")
         == JMAP_OK);
  assert(jmap_message_set_str(m, JMAP_MSG_SENT_MAILBOX, "mb-sent")
         == JMAP_OK);
  assert(jmap_message_set_str(m, JMAP_MSG_FROM, "me@example.com")
         == JMAP_OK);
  assert(jmap_message_set_str(m, JMAP_MSG_BCC, "dana@example.com")
         == JMAP_OK);
  /* Set twice: the second value replaces the first outright. The stale
   * values are asserted ABSENT from the wire below, so a setter that
   * appends, or that leaves a stale sibling slot behind, fails here
   * instead of passing quietly. */
  assert(jmap_message_set_str(m, JMAP_MSG_TO, "stale@example.com")
         == JMAP_OK);
  assert(jmap_message_set_str(m, JMAP_MSG_TO, "you@example.com")
         == JMAP_OK);
  /* Append extends the role that set just replaced: BOTH addresses are
   * asserted on the wire below, so an append that behaves as a set
   * fails here. */
  assert(jmap_message_add_str(m, JMAP_MSG_TO, "also@example.com")
         == JMAP_OK);
  /* And a set AFTER an append collapses the role back to the single
   * address supplied: the appended one is asserted absent below, so a
   * set that behaves as an append fails here. */
  assert(jmap_message_add_str(m, JMAP_MSG_CC, "collapsed@example.com")
         == JMAP_OK);
  assert(jmap_message_set_str(m, JMAP_MSG_CC, "carol@example.com")
         == JMAP_OK);
  assert(jmap_message_set_str(m, JMAP_MSG_SUBJECT, "stale subject")
         == JMAP_OK);
  assert(jmap_message_set_str(m, JMAP_MSG_SUBJECT, "live subject")
         == JMAP_OK);
  assert(jmap_message_set_str(m, JMAP_MSG_BODY, "live body text.")
         == JMAP_OK);

  const char *bodies[] = { SESSION_JSON, SEND_JSON };
  canned_state st = { bodies, 2, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);
  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  jmap_send_result *r = NULL;
  assert(jmap_send(NULL, acct, m, &r) == JMAP_E_MISUSE);
  assert(jmap_send(c, acct, NULL, &r) == JMAP_E_MISUSE);
  assert(jmap_send(c, acct, m, NULL) == JMAP_E_MISUSE);
  assert(r == NULL);

  assert(jmap_send(c, acct, m, &r) == JMAP_OK);
  assert(jmap_send_result_email_id(r) != NULL);
  assert(jmap_send_result_submission_id(r) != NULL);
  assert(jmap_send_result_email_id(NULL) == NULL);
  assert(jmap_send_result_submission_id(NULL) == NULL);

  /* Every value a verb took reached the wire, in the role it was named
   * for; a role that was set then appended carries BOTH addresses; a
   * role that was appended then set carries only the set one; and a
   * rejected call left nothing behind. */
  assert(strstr(st.last_request, "identity-1") != NULL);
  assert(strstr(st.last_request, "mb-drafts") != NULL);
  assert(strstr(st.last_request, "mb-sent") != NULL);
  assert(strstr(st.last_request, "live subject") != NULL);
  assert(strstr(st.last_request, "live body text.") != NULL);
  assert(role_carries(st.last_request, "\"from\"", "me@example.com"));
  assert(role_carries(st.last_request, "\"to\"", "you@example.com"));
  assert(role_carries(st.last_request, "\"to\"", "also@example.com"));
  assert(role_carries(st.last_request, "\"cc\"", "carol@example.com"));
  assert(role_carries(st.last_request, "\"bcc\"", "dana@example.com"));
  assert(strstr(st.last_request, "stale@example.com") == NULL);
  assert(strstr(st.last_request, "stale subject") == NULL);
  assert(strstr(st.last_request, "collapsed@example.com") == NULL);
  assert(strstr(st.last_request, "rejected-append") == NULL);
  assert(strstr(st.last_request, "rejected-ordinal") == NULL);

  jmap_send_result_free(r);
  jmap_send_result_free(NULL);
  jmap_message_free(m);

  /* A message missing a required value is refused before any network
   * traffic, and the client's error slot names which value. The canned
   * script is exhausted by now, so a request that escaped this guard
   * would answer JMAP_E_TRANSPORT rather than the status asserted --
   * and last_request would move off NULL. */
  free(st.last_request);
  st.last_request = NULL;
  jmap_message *partial = NULL;
  jmap_send_result *none = NULL;
  assert(jmap_message_new(&partial) == JMAP_OK);
  assert(jmap_message_set_str(partial, JMAP_MSG_IDENTITY_ID, "identity-1")
         == JMAP_OK);
  assert(jmap_send(c, acct, partial, &none) == JMAP_E_MISUSE);
  assert(none == NULL);
  assert(st.last_request == NULL);
  assert(strstr(jmap_errmsg(c), "JMAP_MSG_DRAFTS_MAILBOX") != NULL);
  jmap_message_free(partial);
  jmap_message_free(NULL);

  /* A malformed recipient is the substrate's parse, on the validation
   * rail, and still pre-wire. */
  jmap_message *bad = NULL;
  assert(jmap_message_new(&bad) == JMAP_OK);
  assert(jmap_message_set_str(bad, JMAP_MSG_IDENTITY_ID, "identity-1")
         == JMAP_OK);
  assert(jmap_message_set_str(bad, JMAP_MSG_DRAFTS_MAILBOX, "mb-drafts")
         == JMAP_OK);
  assert(jmap_message_set_str(bad, JMAP_MSG_SENT_MAILBOX, "mb-sent")
         == JMAP_OK);
  assert(jmap_message_set_str(bad, JMAP_MSG_FROM, "me@example.com")
         == JMAP_OK);
  assert(jmap_message_set_str(bad, JMAP_MSG_TO, "") == JMAP_OK);
  assert(jmap_send(c, acct, bad, &none) == JMAP_E_VALIDATION);
  assert(none == NULL);
  assert(st.last_request == NULL);
  assert(strlen(jmap_errmsg(c)) > 0);
  jmap_message_free(bad);

  jmap_client_free(c);
  free(st.last_request); free(st.last_url);
  jmap_cleanup();
  printf("t12 ok\n");
  return 0;
}
