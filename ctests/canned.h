/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
/*
 * Canned C transport for the compliance tests: replays scripted
 * responses in order, captures the last request body for wire-shape
 * assertions, and counts close calls. The library COPIES response
 * buffers and frees them with free(), so every buffer handed back is
 * strdup'd here.
 */
#ifndef JMAP_CANNED_H
#define JMAP_CANNED_H
#include <stdlib.h>
#include <string.h>
#include "jmap_client.h"

typedef struct {
  const char **bodies;   /* scripted response bodies, replayed in order */
  int count;
  int next;
  char *last_request;    /* strdup of the most recent request body */
  char *last_url;
  int closes;            /* how many times close fired */
} canned_state;

static jmap_transport_code canned_send(void *userdata,
                                       jmap_http_method method,
                                       const char *url,
                                       const char *body,
                                       const char *authorization,
                                       int *out_http_status,
                                       char **out_content_type,
                                       char **out_body) {
  canned_state *st = (canned_state *)userdata;
  (void)method;
  (void)authorization;
  free(st->last_request);
  free(st->last_url);
  st->last_request = strdup(body ? body : "");
  st->last_url = strdup(url ? url : "");
  if (st->next >= st->count) return JMAP_TRANSPORT_NETWORK;
  *out_http_status = 200;
  *out_content_type = strdup("application/json");
  *out_body = strdup(st->bodies[st->next++]);
  return JMAP_TRANSPORT_OK;
}

static inline jmap_transport_code canned_fail_send(void *userdata,
                                            jmap_http_method method,
                                            const char *url,
                                            const char *body,
                                            const char *authorization,
                                            int *out_http_status,
                                            char **out_content_type,
                                            char **out_body) {
  (void)userdata; (void)method; (void)url; (void)body;
  (void)authorization; (void)out_http_status; (void)out_content_type;
  (void)out_body;
  return JMAP_TRANSPORT_NETWORK;
}

static void canned_close(void *userdata) {
  if (userdata) ((canned_state *)userdata)->closes++;
}

static jmap_transport *canned_make_transport(canned_state *st) {
  jmap_transport *t = NULL;
  if (jmap_transport_new(canned_send, canned_close, st, &t) != JMAP_OK)
    return NULL;
  return t;
}
#endif /* JMAP_CANNED_H */
