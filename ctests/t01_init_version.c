/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "jmap_client.h"

/* The status ordinals are the ABI. Pre-1.0 they are not frozen, so
 * these assertions exist to make a renumber a deliberate act: the
 * value beside each name has to be edited here too. */
_Static_assert(JMAP_OK == 0, "ordinal locked");
_Static_assert(JMAP_E_VALIDATION == 1, "ordinal locked");
_Static_assert(JMAP_E_TRANSPORT == 2, "ordinal locked");
_Static_assert(JMAP_E_REQUEST == 3, "ordinal locked");
_Static_assert(JMAP_E_SESSION == 4, "ordinal locked");
_Static_assert(JMAP_E_MISUSE == 5, "ordinal locked");
_Static_assert(JMAP_E_PROTOCOL == 6, "ordinal locked");
_Static_assert(JMAP_E_METHOD == 7, "ordinal locked");
_Static_assert(JMAP_E_SET == 8, "ordinal locked");
_Static_assert(JMAP_CLIENT_VERSION_MAJOR == 0, "version macro");
_Static_assert(JMAP_CLIENT_VERSION_MINOR == 1, "version macro");
_Static_assert(JMAP_CLIENT_VERSION_PATCH == 0, "version macro");

int main(void) {
  /* strerror and version are static and callable BEFORE jmap_init. */
  for (int c = 0; c <= 8; c++) {
    const char *m = jmap_strerror((jmap_status)c);
    assert(m != NULL && strlen(m) > 0);
  }
  assert(strcmp(jmap_strerror((jmap_status)999), "unknown status code") == 0);
  assert(strcmp(jmap_version(), "0.1.0") == 0);

  assert(jmap_init() == JMAP_OK);
  assert(jmap_init() == JMAP_OK); /* idempotent */
  jmap_cleanup();
  printf("t01 ok\n");
  return 0;
}
