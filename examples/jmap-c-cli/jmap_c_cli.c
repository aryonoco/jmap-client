/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
/*
 * jmap-c-cli — the C consumer bench. Every awkward call site here is a
 * bug against the C API design, exactly as the Nim bench is for the
 * Nim surface.
 *
 *   jmap-c-cli mailboxes
 *   jmap-c-cli search <text>
 *   jmap-c-cli read <email-id>
 *   jmap-c-cli flag <email-id>
 *   jmap-c-cli move <email-id> <mailbox-id>
 *   jmap-c-cli sync [since-state]
 *   jmap-c-cli send <to> <subject> <body>
 *   jmap-c-cli vacation <on|off> [subject] [body]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "jmap_client.h"

static jmap_client *g_client;
static const char *g_account;

/*
 * Report a failure of a call that reached the client, so the client's
 * error slot holds the detail. The borrow dies on the next fallible
 * call, which is why it is printed here and never stored.
 */
static int die(const char *what, jmap_status s) {
  fprintf(stderr, "%s: %s (%s)\n", what,
          g_client ? jmap_errmsg(g_client) : "-", jmap_strerror(s));
  return 1;
}

/*
 * The query, message and vacation-update builders carry no error slot,
 * so a setter that fails leaves the client's error text alone. Routing
 * such a failure through die() would print whatever the previous call
 * left behind, so these get the status text on its own.
 */
static int die_status(const char *what, jmap_status s) {
  fprintf(stderr, "%s: %s\n", what, jmap_strerror(s));
  return 1;
}

/*
 * Copy a borrow out of a handle before the handle is freed. There is no
 * length accessor anywhere in the header, so the caller has to pick a
 * cap and then prove it was big enough.
 */
static int copy_borrow(char *out, size_t cap, const char *borrow,
                       const char *what) {
  int n;
  if (borrow == NULL) {
    fprintf(stderr, "%s: the server did not send it\n", what);
    return 1;
  }
  n = snprintf(out, cap, "%s", borrow);
  if (n < 0 || (size_t)n >= cap) {
    fprintf(stderr, "%s: too long for this bench's buffer\n", what);
    return 1;
  }
  return 0;
}

static int connect_from_env(void) {
  const char *url = getenv("JMAP_TEST_STALWART_SESSION_URL");
  const char *user = getenv("JMAP_TEST_STALWART_ALICE_USER");
  const char *pass = getenv("JMAP_TEST_STALWART_ALICE_PASSWORD");
  jmap_status s;
  if (!url || !user || !pass) {
    fprintf(stderr, "set JMAP_TEST_STALWART_SESSION_URL, "
                    "JMAP_TEST_STALWART_ALICE_USER and "
                    "JMAP_TEST_STALWART_ALICE_PASSWORD (source the server "
                    "env file written by just stalwart-up)\n");
    return 1;
  }
  s = jmap_client_new(url, user, pass, NULL, &g_client);
  if (s != JMAP_OK) return die("connect", s);
  s = jmap_client_primary_account(g_client, &g_account);
  if (s != JMAP_OK) return die("primary account", s);
  return 0;
}

static int cmd_mailboxes(void) {
  jmap_mailboxes *mbs = NULL;
  size_t i;
  jmap_status s = jmap_get_mailboxes(g_client, g_account, &mbs);
  if (s != JMAP_OK) return die("Mailbox/get", s);
  for (i = 0; i < jmap_mailboxes_count(mbs); i++) {
    const jmap_mailbox *mb = jmap_mailboxes_at(mbs, i);
    printf("%s  %s (%s) unread %lld/%lld\n", jmap_mailbox_id(mb),
           jmap_mailbox_name(mb), jmap_mailbox_role_identifier(mb),
           (long long)jmap_mailbox_unread_emails(mb),
           (long long)jmap_mailbox_total_emails(mb));
  }
  jmap_mailboxes_free(mbs);
  return 0;
}

/*
 * The header puts the record id in the same group as every other
 * optional field: these getters return NULL when the server left the
 * field out, and preview is named as the only exception. So the id is
 * guarded like the rest.
 */
static void print_email_line(const jmap_email *e) {
  const char *id = jmap_email_id(e);
  const char *subj = jmap_email_subject(e);
  const char *from = jmap_email_from_email(e);
  printf("%s  %s  (%s)\n", id ? id : "(no id)", subj ? subj : "(no subject)",
         from ? from : "?");
}

static int cmd_search(const char *text) {
  jmap_query *q = NULL;
  jmap_emails *es = NULL;
  size_t i;
  jmap_status s = jmap_query_new(&q);
  if (s != JMAP_OK) return die_status("query new", s);
  s = jmap_query_set_str(q, JMAP_Q_TEXT, text);
  if (s == JMAP_OK) s = jmap_query_set_u32(q, JMAP_Q_LIMIT, 20);
  if (s == JMAP_OK)
    s = jmap_query_set_u32(q, JMAP_Q_SORT, JMAP_SORT_RECEIVED_AT_DESC);
  if (s != JMAP_OK) {
    jmap_query_free(q);
    return die_status("query option", s);
  }
  s = jmap_query_emails(g_client, g_account, q, &es);
  jmap_query_free(q);
  if (s != JMAP_OK) return die("Email/query", s);
  for (i = 0; i < jmap_emails_count(es); i++)
    print_email_line(jmap_emails_at(es, i));
  jmap_emails_free(es);
  return 0;
}

static int cmd_read(const char *id) {
  const char *ids[] = { id };
  jmap_emails *es = NULL;
  const jmap_email *e;
  const char *date;
  const char *body;
  size_t missing, i;
  jmap_status s = jmap_get_emails(g_client, g_account, ids, 1, &es);
  if (s != JMAP_OK) return die("Email/get", s);
  /* A get answers with two lists: the records it found, and the ids it
   * did not recognise. A well-formed id that names nothing lands in the
   * second one and is not an error. */
  missing = jmap_emails_notfound_count(es);
  for (i = 0; i < missing; i++)
    fprintf(stderr, "not found: %s\n", jmap_emails_notfound_at(es, i));
  if (jmap_emails_count(es) == 0) {
    if (missing == 0)
      fprintf(stderr, "%s: neither a record nor a notFound entry\n", id);
    jmap_emails_free(es);
    return 1;
  }
  e = jmap_emails_at(es, 0);
  print_email_line(e);
  date = jmap_email_received_at(e);
  if (date) printf("date: %s\n", date);
  body = jmap_email_text_body(e);
  printf("\n%s\n", body ? body : "(no text body)");
  jmap_emails_free(es);
  return 0;
}

/*
 * A write that returns JMAP_OK still has to be read id by id: the
 * server answers each id on its own, and the lists come back in its
 * order, not the order the ids went out in.
 */
static int print_set_result(jmap_set_result *r, const char *verb) {
  size_t i;
  size_t failures;
  for (i = 0; i < jmap_set_result_updated_count(r); i++)
    printf("%s: %s\n", verb, jmap_set_result_updated_at(r, i));
  for (i = 0; i < jmap_set_result_failure_count(r); i++)
    fprintf(stderr, "failed %s: %s (%s)\n", verb,
            jmap_set_result_failure_id_at(r, i),
            jmap_set_result_failure_type_at(r, i));
  failures = jmap_set_result_failure_count(r);
  jmap_set_result_free(r);
  return failures == 0 ? 0 : 1;
}

static int cmd_flag(const char *id) {
  const char *ids[] = { id };
  jmap_set_result *r = NULL;
  jmap_status s = jmap_mark_read(g_client, g_account, ids, 1, &r);
  if (s != JMAP_OK) return die("Email/set", s);
  return print_set_result(r, "flagged");
}

static int cmd_move(const char *id, const char *mailbox_id) {
  const char *ids[] = { id };
  jmap_set_result *r = NULL;
  jmap_status s = jmap_move_emails(g_client, g_account, ids, 1,
                                   mailbox_id, &r);
  if (s != JMAP_OK) return die("Email/set", s);
  return print_set_result(r, "moved");
}

static int cmd_sync(const char *maybe_state) {
  jmap_sync *sy = NULL;
  const jmap_emails *created;
  const jmap_emails *updated;
  jmap_status s;
  size_t i;
  if (maybe_state == NULL) {
    const char *state = NULL;
    s = jmap_get_email_state(g_client, g_account, &state);
    if (s != JMAP_OK) return die("state bootstrap", s);
    printf("state: %s\n", state);
    printf("run again with this state to sync from it\n");
    return 0;
  }
  s = jmap_sync_emails(g_client, g_account, maybe_state, &sy);
  if (s != JMAP_OK) {
    /* A method error is the one failure here with a recovery, and
     * telling it apart needs the wire type rather than the prose. */
    const char *type = s == JMAP_E_METHOD ? jmap_errtype(g_client) : NULL;
    if (type && strcmp(type, "cannotCalculateChanges") == 0) {
      fprintf(stderr, "sync: the server can no longer work out the changes "
                      "since that state. Nothing built from it survives — "
                      "discard it and take a fresh state with `sync` and no "
                      "argument.\n");
      return 1;
    }
    if (type) fprintf(stderr, "sync: method error %s\n", type);
    return die("sync", s);
  }
  created = jmap_sync_created(sy);
  updated = jmap_sync_updated(sy);
  for (i = 0; i < jmap_emails_count(created); i++) {
    printf("new: ");
    print_email_line(jmap_emails_at(created, i));
  }
  for (i = 0; i < jmap_emails_count(updated); i++) {
    printf("changed: ");
    print_email_line(jmap_emails_at(updated, i));
  }
  for (i = 0; i < jmap_sync_destroyed_count(sy); i++)
    printf("gone: %s\n", jmap_sync_destroyed_at(sy, i));
  printf("state: %s -> %s%s\n", jmap_sync_old_state(sy),
         jmap_sync_new_state(sy),
         jmap_sync_has_more(sy) ? " (more changes pending)" : "");
  jmap_sync_free(sy);
  return 0;
}

/*
 * Roles are the only stable way to name Drafts and Sent, and there is
 * no lookup for one — the whole mailbox list is fetched and walked, and
 * the id copied out before the list is freed.
 */
static int find_role_mailbox(jmap_mailbox_role role, char *out, size_t cap) {
  jmap_mailboxes *mbs = NULL;
  size_t count, i;
  int found = 0;
  int rc = 1;
  jmap_status s = jmap_get_mailboxes(g_client, g_account, &mbs);
  if (s != JMAP_OK) return die("Mailbox/get", s);
  count = jmap_mailboxes_count(mbs);
  for (i = 0; i < count; i++) {
    const jmap_mailbox *mb = jmap_mailboxes_at(mbs, i);
    if (jmap_mailbox_role_get(mb) == role) {
      found = 1;
      rc = copy_borrow(out, cap, jmap_mailbox_id(mb), "mailbox id");
      break;
    }
  }
  jmap_mailboxes_free(mbs);
  if (!found) fprintf(stderr, "no mailbox with the required role\n");
  return rc;
}

static int cmd_send(const char *to, const char *subject, const char *body) {
  /* The sender identity and the Drafts/Sent mailboxes all come from
   * the API — nothing configured out of band. */
  jmap_identities *ids = NULL;
  jmap_send_result *r = NULL;
  jmap_message *m = NULL;
  const jmap_identity *ident;
  char identity_id[256], from_addr[512], drafts[256], sent[256];
  int failed;
  jmap_status s = jmap_get_identities(g_client, g_account, &ids);
  if (s != JMAP_OK) return die("Identity/get", s);
  if (jmap_identities_count(ids) == 0) {
    fprintf(stderr, "no sending identity on this account\n");
    jmap_identities_free(ids);
    return 1;
  }
  ident = jmap_identities_at(ids, 0);
  failed = copy_borrow(identity_id, sizeof identity_id,
                       jmap_identity_id(ident), "identity id");
  if (!failed)
    failed = copy_borrow(from_addr, sizeof from_addr,
                         jmap_identity_email(ident), "identity address");
  jmap_identities_free(ids);
  if (failed) return 1;
  if (find_role_mailbox(JMAP_ROLE_DRAFTS, drafts, sizeof drafts)) return 1;
  if (find_role_mailbox(JMAP_ROLE_SENT, sent, sizeof sent)) return 1;

  s = jmap_message_new(&m);
  if (s != JMAP_OK) return die_status("message", s);
  /* Every value is named where it is supplied: nothing here can be
   * transposed with its neighbour the way a wide argument list allows. */
  s = jmap_message_set_str(m, JMAP_MSG_IDENTITY_ID, identity_id);
  if (s == JMAP_OK) s = jmap_message_set_str(m, JMAP_MSG_DRAFTS_MAILBOX,
                                             drafts);
  if (s == JMAP_OK) s = jmap_message_set_str(m, JMAP_MSG_SENT_MAILBOX, sent);
  if (s == JMAP_OK) s = jmap_message_set_str(m, JMAP_MSG_FROM, from_addr);
  if (s == JMAP_OK) s = jmap_message_set_str(m, JMAP_MSG_TO, to);
  if (s == JMAP_OK) s = jmap_message_set_str(m, JMAP_MSG_SUBJECT, subject);
  if (s == JMAP_OK) s = jmap_message_set_str(m, JMAP_MSG_BODY, body);
  if (s != JMAP_OK) {
    jmap_message_free(m);
    return die_status("message", s);
  }
  s = jmap_send(g_client, g_account, m, &r);
  jmap_message_free(m);
  if (s != JMAP_OK) {
    /* A refused create names its reason, and the reasons differ in what
     * the user should do next — free space, or shrink the message — so
     * print the type alongside the server's prose. */
    if (s == JMAP_E_SET) {
      const char *type = jmap_errtype(g_client);
      if (type) fprintf(stderr, "send: refused with %s\n", type);
    }
    return die("send", s);
  }
  printf("sent: %s (submission %s)\n", jmap_send_result_email_id(r),
         jmap_send_result_submission_id(r));
  jmap_send_result_free(r);
  return 0;
}

static int cmd_vacation(jmap_vacation_state vs, const char *subject,
                        const char *body) {
  jmap_vacation_update *u = NULL;
  jmap_set_result *r = NULL;
  jmap_status s = jmap_vacation_update_new(&u);
  if (s != JMAP_OK) return die_status("vacation update", s);
  s = jmap_vacation_update_set_enabled(u, vs);
  /* An omitted argument leaves the property alone. This bench has no
   * spelling for "clear it" — the setters do (NULL), the argv shape
   * does not. */
  if (s == JMAP_OK && subject)
    s = jmap_vacation_update_set_subject(u, subject);
  if (s == JMAP_OK && body)
    s = jmap_vacation_update_set_text_body(u, body);
  if (s != JMAP_OK) {
    jmap_vacation_update_free(u);
    return die_status("vacation update", s);
  }
  s = jmap_set_vacation(g_client, g_account, u, &r);
  jmap_vacation_update_free(u);
  if (s != JMAP_OK) return die("VacationResponse/set", s);
  return print_set_result(r, "vacation updated");
}

static int usage(void) {
  fprintf(stderr,
          "usage: jmap-c-cli mailboxes | search <text> | read <id> |\n"
          "       flag <id> | move <id> <mailbox-id> | sync [state] |\n"
          "       send <to> <subject> <body> | vacation <on|off> "
          "[subject] [body]\n");
  return 2;
}

typedef enum {
  CMD_NONE = 0,
  CMD_MAILBOXES,
  CMD_SEARCH,
  CMD_READ,
  CMD_FLAG,
  CMD_MOVE,
  CMD_SYNC,
  CMD_SEND,
  CMD_VACATION_ON,
  CMD_VACATION_OFF
} command;

/*
 * The command line is settled before anything connects, so a typo costs
 * no round trip and always reaches the usage text rather than a
 * complaint about the environment.
 */
static command parse_command(int argc, char **argv) {
  const char *verb = argv[1];
  if (strcmp(verb, "mailboxes") == 0 && argc == 2) return CMD_MAILBOXES;
  if (strcmp(verb, "search") == 0 && argc == 3) return CMD_SEARCH;
  if (strcmp(verb, "read") == 0 && argc == 3) return CMD_READ;
  if (strcmp(verb, "flag") == 0 && argc == 3) return CMD_FLAG;
  if (strcmp(verb, "move") == 0 && argc == 4) return CMD_MOVE;
  if (strcmp(verb, "sync") == 0 && argc <= 3) return CMD_SYNC;
  if (strcmp(verb, "send") == 0 && argc == 5) return CMD_SEND;
  if (strcmp(verb, "vacation") == 0 && argc >= 3 && argc <= 5) {
    if (strcmp(argv[2], "on") == 0) return CMD_VACATION_ON;
    if (strcmp(argv[2], "off") == 0) return CMD_VACATION_OFF;
  }
  return CMD_NONE;
}

static int dispatch(command cmd, int argc, char **argv) {
  switch (cmd) {
  case CMD_MAILBOXES: return cmd_mailboxes();
  case CMD_SEARCH: return cmd_search(argv[2]);
  case CMD_READ: return cmd_read(argv[2]);
  case CMD_FLAG: return cmd_flag(argv[2]);
  case CMD_MOVE: return cmd_move(argv[2], argv[3]);
  case CMD_SYNC: return cmd_sync(argc == 3 ? argv[2] : NULL);
  case CMD_SEND: return cmd_send(argv[2], argv[3], argv[4]);
  case CMD_VACATION_ON:
    return cmd_vacation(JMAP_VACATION_ENABLED, argc >= 4 ? argv[3] : NULL,
                        argc >= 5 ? argv[4] : NULL);
  case CMD_VACATION_OFF:
    return cmd_vacation(JMAP_VACATION_DISABLED, argc >= 4 ? argv[3] : NULL,
                        argc >= 5 ? argv[4] : NULL);
  case CMD_NONE: break;
  }
  return usage();
}

int main(int argc, char **argv) {
  jmap_status init;
  command cmd;
  int rc;
  if (argc < 2) return usage();
  cmd = parse_command(argc, argv);
  if (cmd == CMD_NONE) return usage();
  init = jmap_init();
  if (init != JMAP_OK) {
    fprintf(stderr, "jmap_init: %s\n", jmap_strerror(init));
    return 1;
  }
  rc = connect_from_env();
  if (rc == 0) rc = dispatch(cmd, argc, argv);
  /* Free before jmap_cleanup(), on every path: the header forbids
   * tearing the library down while a handle is still alive. */
  jmap_client_free(g_client);
  jmap_cleanup();
  return rc;
}
