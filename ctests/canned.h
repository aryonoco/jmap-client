/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Aryan Ameri */
/*
 * Canned C transports for the compliance tests: each replays scripted
 * responses in order, captures the last request body for wire-shape
 * assertions, and counts close calls. The library COPIES response
 * buffers and frees them with free(), so every buffer handed back is
 * strdup'd here.
 */
#ifndef JMAP_CANNED_H
#define JMAP_CANNED_H
#include "jmap_client.h"
#include <stdlib.h>
#include <string.h>

typedef struct {
  const char **bodies; /* scripted response bodies, replayed in order */
  int count;
  int next;
  char *last_request; /* strdup of the most recent request body */
  char *last_url;
  int closes; /* how many times close fired */
} canned_state;

static inline void canned_capture(char **last_request, char **last_url,
                                  const char *url, const char *body) {
  /* jmap_client.h guarantees url and body are non-NULL borrows (a GET
   * body is "", never NULL), so no defensive NULL check is needed
   * before strdup here. */
  free(*last_request);
  free(*last_url);
  *last_request = strdup(body);
  *last_url = strdup(url);
}

/*
 * canned_send, canned_close and canned_make_transport are one set.
 * Each close callback casts the userdata back to the state its own
 * send was written for, and the two states in this file hold their
 * fields in the same order, so a mismatched pair -- canned_reply_send
 * with canned_close, say -- would find a plausible int at the right
 * offset and count closes into the wrong struct without any of it
 * showing: a wrong-type cast over a compatible layout is invisible to
 * ASan and UBSan alike. Build a transport with the make_transport of
 * the set you want; that is where the pairing is made, and it takes
 * the state by its own type.
 */
static inline jmap_transport_code
canned_send(void *userdata, jmap_http_method method, const char *url,
            const char *body, const char *authorization, int *out_http_status,
            char **out_content_type, char **out_body) {
  canned_state *st = (canned_state *)userdata;
  (void)method;
  (void)authorization;
  canned_capture(&st->last_request, &st->last_url, url, body);
  if (st->next >= st->count)
    return JMAP_TRANSPORT_NETWORK;
  *out_http_status = 200;
  *out_content_type = strdup("application/json");
  *out_body = strdup(st->bodies[st->next++]);
  return JMAP_TRANSPORT_OK;
}

static inline jmap_transport_code
canned_fail_send(void *userdata, jmap_http_method method, const char *url,
                 const char *body, const char *authorization,
                 int *out_http_status, char **out_content_type,
                 char **out_body) {
  (void)userdata;
  (void)method;
  (void)url;
  (void)body;
  (void)authorization;
  (void)out_http_status;
  (void)out_content_type;
  (void)out_body;
  return JMAP_TRANSPORT_NETWORK;
}

static inline void canned_close(void *userdata) {
  if (userdata)
    ((canned_state *)userdata)->closes++;
}

static inline jmap_transport *canned_make_transport(canned_state *st) {
  jmap_transport *t = NULL;
  if (jmap_transport_new(canned_send, canned_close, st, &t) != JMAP_OK)
    return NULL;
  return t;
}

/*
 * The same replay, for a test that needs the HTTP status line or the
 * Content-Type to be something other than a 200 carrying JSON -- the
 * two the library classifies a response by before it ever looks at the
 * body. A zero http_status means 200 and a NULL content_type means
 * "application/json", so a scripted reply that cares about neither is
 * written { .body = ... } and replays exactly as canned_send would.
 */
typedef struct {
  const char *body;
  int http_status;
  const char *content_type;
} canned_reply;

typedef struct {
  const canned_reply *replies; /* scripted responses, replayed in order */
  int count;
  int next;
  char *last_request; /* strdup of the most recent request body */
  char *last_url;
  int closes; /* how many times close fired */
} canned_reply_state;

/*
 * The second set, under the same rule as the first: this send, this
 * close and this make_transport go together.
 */
static inline jmap_transport_code
canned_reply_send(void *userdata, jmap_http_method method, const char *url,
                  const char *body, const char *authorization,
                  int *out_http_status, char **out_content_type,
                  char **out_body) {
  canned_reply_state *st = (canned_reply_state *)userdata;
  (void)method;
  (void)authorization;
  canned_capture(&st->last_request, &st->last_url, url, body);
  if (st->next >= st->count)
    return JMAP_TRANSPORT_NETWORK;
  const canned_reply *reply = &st->replies[st->next++];
  *out_http_status = reply->http_status ? reply->http_status : 200;
  *out_content_type =
      strdup(reply->content_type ? reply->content_type : "application/json");
  *out_body = strdup(reply->body);
  return JMAP_TRANSPORT_OK;
}

static inline void canned_reply_close(void *userdata) {
  if (userdata)
    ((canned_reply_state *)userdata)->closes++;
}

static inline jmap_transport *
canned_reply_make_transport(canned_reply_state *st) {
  jmap_transport *t = NULL;
  if (jmap_transport_new(canned_reply_send, canned_reply_close, st, &t) !=
      JMAP_OK)
    return NULL;
  return t;
}
#endif /* JMAP_CANNED_H */
