discard """
  action: "reject"
  errormsg: "the field 'rawKind' is not accessible."
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A30b reject — the sealed ``SubmissionParam`` cannot be raw-constructed
## across module boundaries. Before A30b a caller could write
## ``SubmissionParam(kind: spkNotify, notifyFlags: {})`` and put an empty,
## wire-invalid ``NOTIFY=`` onto an ``Envelope`` (RFC 3461 §4.1 demands a
## non-empty set). The discriminator and every arm field are now
## module-private (``rawKind`` / ``raw*``); the only producers reachable from
## ``import jmap_client`` are the smart constructors — and ``notifyParam``
## delegates the non-empty + ``NEVER``-exclusivity invariant to
## ``parseNotifySet``. A compile success here would mean the seal has drifted
## and the empty-``NOTIFY`` hole had reopened (P15/P16).

import jmap_client
discard SubmissionParam(rawKind: spkNotify)
