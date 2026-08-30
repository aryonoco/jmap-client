<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# jmap-c-cli — the C consumer bench

A plain-C command-line program that drives the library through
`include/jmap_client.h` and nothing else. It is the C counterpart of the
Nim bench in [`examples/jmap-cli`](../jmap-cli): both exist to be
written, not to be used, so that the friction of writing them is
measured before the surface settles.

The library is pre-1.0 (version `0.1.0`). Nothing here is a stability or
compatibility promise; the C ABI may still change.

## Build

    just build-c-bench

That builds `bin/libjmap_client.so` first, then compiles the bench with
`gcc -std=c99 -Wall -Wextra -Werror` against the shipped header and
links it against the shared library with an rpath into `bin/`. The
result is `bin/jmap-c-cli`.

Building the bench is a spot check of the header: it is written from
outside the library, against the header alone, so a declaration the
bench calls that no longer matches the library fails the build. The
bench calls about two thirds of the exported functions — 71 of 102 at
the time of writing — so this is a spot check and not a drift gate.
`just lint-c-header-snapshot` and `just lint-c-header-types` are the
gates, and they run earlier in the same CI job. CI builds the bench and
never runs it: running it needs a live JMAP server.

To run it under the sanitizers, compile the same source by hand:

    gcc -std=c99 -Wall -Wextra -Werror -g -fsanitize=address,undefined \
        -Iinclude examples/jmap-c-cli/jmap_c_cli.c \
        -Lbin -ljmap_client -Wl,-rpath,"$PWD/bin" -o /tmp/jmap-c-cli-asan

The shared library is built with `-d:useMalloc`, so LeakSanitizer sees
allocations on both sides of the boundary, not only the C side.

## Run against a live server

    just stalwart-up
    source /tmp/stalwart-env.sh
    bin/jmap-c-cli mailboxes
    bin/jmap-c-cli search <text>
    bin/jmap-c-cli read <email-id>
    bin/jmap-c-cli flag <email-id>
    bin/jmap-c-cli move <email-id> <mailbox-id>
    bin/jmap-c-cli sync                  # prints the current Email state
    bin/jmap-c-cli sync <since-state>    # the delta since that state
    bin/jmap-c-cli send <to> <subject> <body>
    bin/jmap-c-cli vacation on|off [subject] [body]

Connection details are read from the same three environment variables
the Nim bench reads, so one `source` drives both:
`JMAP_TEST_STALWART_SESSION_URL`, `JMAP_TEST_STALWART_ALICE_USER` and
`JMAP_TEST_STALWART_ALICE_PASSWORD`.

Every command exits non-zero on failure. `2` means the command line was
rejected, before anything connects. `1` means everything else: an unset
environment variable, a call the server refused, an id it did not
recognise, or a write it refused for some of the ids given.

## FINDINGS

Every awkward call site recorded here is a bug against the C API design
— the bench exists to collect exactly these.

- **A failed builder setter has nowhere to report itself.** The query,
  message and vacation-update handles carry no error slot, so the
  status a setter returns is the only report there will ever be, and it
  cannot be routed through `jmap_errmsg()` — that would print whatever
  the previous call on the client left behind. The bench therefore
  carries two failure reporters, `die()` and `die_status()`, and the
  call site has to know which handle it is holding to pick the right
  one. Seven consecutive `if (s == JMAP_OK) s = ...` lines in
  `cmd_send()` are the visible cost.
- **Copying a borrow out means guessing a buffer size.** Ids and
  addresses are borrows into a collection handle, and the send path
  needs four of them to outlive three separate handles. No accessor
  returns a length, so the consumer either picks a cap and checks for
  truncation, as `copy_borrow()` does, or calls `strlen()` and
  `malloc()` for every field it keeps.
- **Two different shapes for one refused write.** A refusal of an id in
  `jmap_mark_emails_read()` or `jmap_move_emails()` is data on the
  result, read with `jmap_set_result_failure_type_at()`. A refusal of
  the one object `jmap_send()` creates is the status `JMAP_E_SET`
  instead, read with `jmap_errtype()`. It is a wire type string either
  way, so the bench writes two code paths to reach one value.
- **Naming a well-known mailbox costs a round trip.** There is no lookup
  by role, so `find_role_mailbox()` fetches every mailbox in the account
  and walks the list — twice per `send`, once for Drafts and once for
  Sent.
- **The record id is guarded like an optional field.** The header says
  of the email getters: "These getters return NULL when the server left
  the field out. `jmap_email_preview()` is the one exception." Preview
  is the only name exempted, so `jmap_email_id()` sits inside that
  group and the bench guards it. RFC 8620 section 5.1 says of the
  `properties` argument to `/get`: "The id property of the object is
  *always* returned, even if not explicitly requested." The library's
  own `jmap_email_id` keeps the presence check anyway, its comment
  saying it will not rely on "a guarantee this proc cannot itself
  enforce". The consumer's cost is that the field it correlates
  everything else by is the one it must null-check first.
- **The bench cannot spell "clear this property".**
  `jmap_vacation_update_set_subject(u, NULL)` clears the subject, which
  is a different request from leaving it alone, but an absent command
  line argument is also NULL. The setters draw the distinction; an argv
  shape cannot.
