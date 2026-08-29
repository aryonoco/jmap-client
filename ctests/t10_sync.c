/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"
#include "canned.h"

static const char *SESSION_JSON = "{\"username\":\"test@example.com\",\"apiUrl\":\"https://jmap.example.com/api/\",\"downloadUrl\":\"https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}\",\"uploadUrl\":\"https://jmap.example.com/upload/{accountId}/\",\"eventSourceUrl\":\"https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}\",\"state\":\"s1\",\"capabilities\":{\"urn:ietf:params:jmap:core\":{\"maxSizeUpload\":50000000,\"maxConcurrentUpload\":4,\"maxSizeRequest\":10000000,\"maxConcurrentRequests\":8,\"maxCallsInRequest\":32,\"maxObjectsInGet\":1000,\"maxObjectsInSet\":500,\"collationAlgorithms\":[\"i;ascii-casemap\",\"i;unicode-casemap\"]}},\"accounts\":{\"A1\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{\"urn:ietf:params:jmap:mail\":{\"maxMailboxesPerEmail\":100,\"maxSizeMailboxName\":490,\"maxSizeAttachmentsPerEmail\":50000000,\"emailQuerySortOptions\":[\"receivedAt\",\"from\"],\"mayCreateTopLevelMailbox\":true}}},\"Z9\":{\"name\":\"test\",\"isPersonal\":true,\"isReadOnly\":false,\"accountCapabilities\":{}}},\"primaryAccounts\":{\"urn:ietf:params:jmap:mail\":\"A1\"}}";
/* Generated via a throwaway nim r script that built these
 * envelopes through the one-shots' own toJson path (accountId
 * swapped to "A1" to match SESSION_JSON above), then round-tripped
 * each back through the real getEmailState/syncEmails one-shots to
 * prove they decode before these literals were pasted in. */
static const char *EMPTY_EMAIL_GET_JSON = "{\"methodResponses\":[[\"Email/get\",{\"accountId\":\"A1\",\"state\":\"s2\",\"list\":[],\"notFound\":[]},\"c0\"]],\"sessionState\":\"s1\"}";
static const char *SYNC_JSON = "{\"methodResponses\":[[\"Email/changes\",{\"accountId\":\"A1\",\"oldState\":\"s2\",\"newState\":\"s3\",\"hasMoreChanges\":false,\"created\":[\"em-new\"],\"updated\":[\"em-upd\"],\"destroyed\":[\"em-gone\"]},\"c0\"],[\"Email/get\",{\"accountId\":\"A1\",\"state\":\"s3\",\"list\":[],\"notFound\":[]},\"c1\"],[\"Email/get\",{\"accountId\":\"A1\",\"state\":\"s3\",\"list\":[],\"notFound\":[]},\"c2\"]],\"sessionState\":\"s1\"}";
/* A second bootstrap response with a different state, used to prove
 * the borrow-invalidation contract without reading a freed pointer. */
static const char *EMPTY_EMAIL_GET_JSON_2 = "{\"methodResponses\":[[\"Email/get\",{\"accountId\":\"A1\",\"state\":\"s4\",\"list\":[],\"notFound\":[]},\"c0\"]],\"sessionState\":\"s1\"}";
/* A server response that tries to claim an empty Email state. */
static const char *EMPTY_STATE_EMAIL_GET_JSON = "{\"methodResponses\":[[\"Email/get\",{\"accountId\":\"A1\",\"state\":\"\",\"list\":[],\"notFound\":[]},\"c0\"]],\"sessionState\":\"s1\"}";

int main(void) {
  assert(jmap_init() == JMAP_OK);
  const char *bodies[] = { SESSION_JSON, EMPTY_EMAIL_GET_JSON, SYNC_JSON,
                           EMPTY_EMAIL_GET_JSON_2 };
  canned_state st = { bodies, 4, 0, NULL, NULL, 0 };
  jmap_transport *t = canned_make_transport(&st);
  jmap_client *c = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t, &c)
         == JMAP_OK);
  jmap_transport_free(t);
  const char *acct = NULL;
  assert(jmap_client_primary_account(c, &acct) == JMAP_OK);

  /* Bootstrap: the cursor for a first sync, borrowed from the client. */
  const char *state = NULL;
  assert(jmap_get_email_state(c, acct, &state) == JMAP_OK);
  assert(state != NULL && strlen(state) > 0);
  /* The bootstrap request fetched no email payload. */
  assert(strstr(st.last_request, "\"ids\":[]") != NULL);
  /* Snapshot the borrow's content now: the header documents it as
   * invalidated by the next fallible call on this handle, so holding
   * the raw pointer past that point is unsupported. */
  char *state_copy = strdup(state);
  assert(state_copy != NULL);

  /* Sync from that cursor: the full fetchable delta in one call. */
  jmap_sync *s = NULL;
  assert(jmap_sync_emails(c, acct, state, &s) == JMAP_OK);
  assert(strlen(jmap_sync_new_state(s)) > 0);
  assert(strcmp(jmap_sync_old_state(s), jmap_sync_new_state(s)) != 0);
  /* The delta's oldState echoes the cursor the sync started from. */
  assert(strcmp(jmap_sync_old_state(s), state_copy) == 0);
  assert(jmap_sync_has_more(s) == 0);
  assert(jmap_sync_destroyed_count(s) == 1);
  assert(jmap_sync_destroyed_at(s, 0) != NULL);
  /* SIZE_MAX must not narrow into range: still NULL, never a crash. */
  assert(jmap_sync_destroyed_at(s, SIZE_MAX) == NULL);

  /* created/updated are borrowed email views owned by the sync. */
  const jmap_emails *created = jmap_sync_created(s);
  const jmap_emails *updated = jmap_sync_updated(s);
  assert(created != NULL && updated != NULL);
  assert(jmap_emails_count(created) == 0); /* canned gets are empty */
  assert(jmap_emails_count(updated) == 0);

  /* Borrow-lifetime proof: jmap_get_email_state's cursor lives in the
   * CLIENT handle's own slot, so a second bootstrap call replaces it.
   * Proven by comparing the earlier snapshot against the fresh value
   * -- never by re-reading the first pointer after it was superseded,
   * which would be a use-after-free rather than a documented use. */
  const char *state2 = NULL;
  assert(jmap_get_email_state(c, acct, &state2) == JMAP_OK);
  assert(strcmp(state2, "s4") == 0);
  assert(strcmp(state_copy, state2) != 0);
  free(state_copy);

  /* By contrast, the sync object's own old/new state borrows belong
   * to the SYNC handle, not the client: the jmap_get_email_state call
   * just above did not disturb them. */
  assert(strcmp(jmap_sync_old_state(s), "s2") == 0);
  assert(strcmp(jmap_sync_new_state(s), "s3") == 0);

  jmap_sync_free(s);
  jmap_sync_free(NULL);
  jmap_client_free(c);
  free(st.last_request); free(st.last_url);

  /* Absent-vs-stale proof: a live JmapState can never stringify to ""
   * -- the substrate's smart constructor refuses an empty state token
   * at decode time -- so a server response that tries to claim one
   * fails the call outright instead of handing back a hollow success.
   * A fresh client keeps this failure unambiguous. */
  const char *bodies2[] = { SESSION_JSON, EMPTY_STATE_EMAIL_GET_JSON };
  canned_state st2 = { bodies2, 2, 0, NULL, NULL, 0 };
  jmap_transport *t2 = canned_make_transport(&st2);
  jmap_client *c2 = NULL;
  assert(jmap_client_new("https://canned.invalid/jmap", "u", "p", t2, &c2)
         == JMAP_OK);
  jmap_transport_free(t2);
  const char *acct2 = NULL;
  assert(jmap_client_primary_account(c2, &acct2) == JMAP_OK);
  const char *bad_state = NULL;
  assert(jmap_get_email_state(c2, acct2, &bad_state) == JMAP_E_PROTOCOL);
  /* Absent stays absent: the out-parameter is untouched on failure,
   * never silently set to an empty string standing in for "no cursor". */
  assert(bad_state == NULL);
  assert(strlen(jmap_errmsg(c2)) > 0);
  jmap_client_free(c2);
  free(st2.last_request); free(st2.last_url);

  jmap_cleanup();
  printf("t10 ok\n");
  return 0;
}
