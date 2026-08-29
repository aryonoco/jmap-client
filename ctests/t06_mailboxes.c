/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";
static const char *MAILBOX_GET_JSON = "{\"methodResponses\":[[\"Mailbox/get\",{\"accountId\":\"A1\",\"state\":\"st2vq\",\"list\":[{\"id\":\"a\",\"name\":\"Inbox\",\"parentId\":null,\"role\":\"inbox\",\"sortOrder\":0,\"isSubscribed\":true,\"totalEmails\":2043,\"unreadEmails\":2013,\"totalThreads\":1865,\"unreadThreads\":1835,\"myRights\":{\"mayReadItems\":true,\"mayAddItems\":true,\"mayRemoveItems\":true,\"maySetSeen\":true,\"maySetKeywords\":true,\"mayCreateChild\":true,\"mayRename\":true,\"maySubmit\":true,\"mayDelete\":true,\"mayShare\":true}},{\"id\":\"q\",\"name\":\"phase-i 49 charlie\",\"parentId\":\"a\",\"role\":null,\"sortOrder\":10,\"isSubscribed\":false,\"totalEmails\":0,\"unreadEmails\":0,\"totalThreads\":0,\"unreadThreads\":0,\"myRights\":{\"mayReadItems\":true,\"mayAddItems\":true,\"mayRemoveItems\":true,\"maySetSeen\":true,\"maySetKeywords\":true,\"mayCreateChild\":true,\"mayRename\":true,\"maySubmit\":true,\"mayDelete\":true,\"mayShare\":true}}],\"notFound\":[]},\"c0\"]],\"sessionState\":\"s1\"}";

int main(void) {
  assert(jmap_init() == JMAP_OK);
  const char *bodies[] = { SESSION_JSON, MAILBOX_GET_JSON };
  canned_state st = { bodies, 2, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);

  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  jmap_mailboxes *mbs = NULL;
  assert(jmap_get_mailboxes(c, acct, &mbs) == JMAP_OK);
  assert(jmap_mailboxes_count(mbs) == 2);

  const jmap_mailbox *inbox = NULL;
  for (size_t i = 0; i < jmap_mailboxes_count(mbs); i++) {
    const jmap_mailbox *mb = jmap_mailboxes_at(mbs, i);
    assert(mb != NULL);
    assert(jmap_mailbox_id(mb) != NULL);
    assert(jmap_mailbox_name(mb) != NULL);
    if (jmap_mailbox_role_get(mb) == JMAP_ROLE_INBOX) inbox = mb;
  }
  assert(inbox != NULL);
  assert(strcmp(jmap_mailbox_role_identifier(inbox), "inbox") == 0);
  assert(jmap_mailbox_unread_emails(inbox) >= 1);
  assert(jmap_mailbox_has_right(inbox, JMAP_RIGHT_READ_ITEMS) == 1);

  /* The role-less child: role NONE, empty identifier, parent set. */
  int saw_child = 0;
  for (size_t i = 0; i < jmap_mailboxes_count(mbs); i++) {
    const jmap_mailbox *mb = jmap_mailboxes_at(mbs, i);
    if (jmap_mailbox_role_get(mb) == JMAP_ROLE_NONE) {
      assert(strcmp(jmap_mailbox_role_identifier(mb), "") == 0);
      assert(jmap_mailbox_parent_id(mb) != NULL);
      saw_child = 1;
    }
  }
  assert(saw_child == 1);

  /* Out of range is NULL, never a crash. SIZE_MAX exercises the
   * unsigned-domain bounds check directly: narrowing to int first
   * would raise a RangeDefect across this raises:[] boundary. */
  assert(jmap_mailboxes_at(mbs, 99) == NULL);
  assert(jmap_mailboxes_at(mbs, SIZE_MAX) == NULL);

  /* Bad account id string is validation, recorded on the handle. */
  jmap_mailboxes *bad = NULL;
  assert(jmap_get_mailboxes(c, "", &bad) == JMAP_E_VALIDATION);
  assert(strlen(jmap_errmsg(c)) > 0);

  jmap_mailboxes_free(mbs);
  jmap_mailboxes_free(NULL);
  jmap_client_free(c);
  free(st.last_request); free(st.last_url);
  jmap_cleanup();
  printf("t06 ok\n");
  return 0;
}
