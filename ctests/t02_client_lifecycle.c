/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include "jmap_client.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  jmap_client *c = NULL;

  /* Before jmap_init, anything touching the runtime is misuse. */
  assert(jmap_client_new("https://example.com/jmap", "u", "p", NULL, &c) ==
         JMAP_E_MISUSE);
  assert(c == NULL);

  assert(jmap_init() == JMAP_OK);

  /* NULL arguments are misuse, detected before any dereference. */
  assert(jmap_client_new(NULL, "u", "p", NULL, &c) == JMAP_E_MISUSE);
  assert(jmap_client_new("https://example.com/jmap", "u", "p", NULL, NULL) ==
         JMAP_E_MISUSE);

  /* A bad URL fails validation pre-handle: code-granular, *out untouched. */
  c = (jmap_client *)0x1;
  assert(jmap_client_new("not a url", "u", "p", NULL, &c) == JMAP_E_VALIDATION);
  assert(c == (jmap_client *)0x1);

  /* A well-formed URL constructs without network IO (lazy session). */
  c = NULL;
  assert(jmap_client_new("https://example.invalid/jmap", "user", "pass", NULL,
                         &c) == JMAP_OK);
  assert(c != NULL);
  assert(strcmp(jmap_errmsg(c), "no error") == 0);

  /* errmsg on NULL is a static string, not a crash. */
  assert(strcmp(jmap_errmsg(NULL), "null client handle") == 0);

  jmap_client_free(c);
  jmap_client_free(NULL); /* idempotent on NULL */
  jmap_cleanup();
  printf("t02 ok\n");
  return 0;
}
