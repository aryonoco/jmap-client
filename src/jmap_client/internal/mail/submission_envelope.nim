# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 8621 §7 EmailSubmission Envelope composition — ``SubmissionAddress``
## (RFC 5321 Mailbox + optional Mail/Rcpt parameters), ``ReversePath``
## (``mailFrom`` accepts the SMTP null path ``<>``), ``NonEmptyRcptList``
## (``rcptTo`` is non-empty by type), and ``Envelope``.
##
## The leaf primitives — RFC 5321 Mailbox grammar, esmtp-keyword atoms, and
## the typed SMTP-parameter algebra — live in sibling modules and are
## re-exported here so a single ``import ./submission_envelope`` continues
## to surface every public name in the EmailSubmission L1 family.
##
## Design authority: ``docs/design/12-mail-G1-design.md`` §2.5.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ../types/validation

import ./submission_mailbox
export submission_mailbox

import ./submission_atoms
export submission_atoms

import ./submission_param
export submission_param

type
  SubmissionAddress* {.ruleOff: "objects".} = object
    ## RFC 8621 §7 Envelope Address — RFC 5321 Mailbox plus optional
    ## Mail/Rcpt parameters. Parameters are nullable per RFC (G34).
    mailbox*: RFC5321Mailbox
    parameters*: Opt[SubmissionParams]

  ReversePathKind* = enum
    ## Discriminator for ``ReversePath``. Names the two shapes of an SMTP
    ## ``Reverse-path`` — the null path ``<>`` and a concrete mailbox.
    rpkNullPath
      ## SMTP null reverse path ``<>``; RFC 5321 §4.1.1.2 permits Mail-parameters here
    rpkMailbox ## Concrete RFC 5321 Mailbox with optional parameters

  ReversePath* {.ruleOff: "objects".} = object
    ## Models SMTP ``Reverse-path = Path / "<>"`` at ``Envelope.mailFrom`` (G32).
    ## Distinguished from ``SubmissionAddress`` so ``rcptTo`` (Forward-path only)
    ## cannot admit empty addresses (G33).
    case kind*: ReversePathKind
    of rpkNullPath: nullPathParams*: Opt[SubmissionParams]
    of rpkMailbox: sender*: SubmissionAddress

  NonEmptyRcptList* = distinct seq[SubmissionAddress]
    ## Enforces 1..N recipient cardinality (RFC 8621 §7 ¶5). Construct
    ## via ``parseNonEmptyRcptList`` (strict) or
    ## ``parseNonEmptyRcptListFromServer`` (lenient, Postel's law).

  Envelope* {.ruleOff: "objects".} = object
    ## RFC 8621 §7 Envelope. ``mailFrom`` accepts the SMTP null path;
    ## ``rcptTo`` is non-empty by type.
    mailFrom*: ReversePath
    rcptTo*: NonEmptyRcptList

func nullReversePath*(
    params: Opt[SubmissionParams] = Opt.none(SubmissionParams)
): ReversePath =
  ## Infallible ctor for the SMTP null reverse path ``<>``.
  ## Default: no Mail-parameters.
  ReversePath(kind: rpkNullPath, nullPathParams: params)

func reversePath*(address: SubmissionAddress): ReversePath =
  ## Lifts an already-validated ``SubmissionAddress`` into ``ReversePath``.
  ReversePath(kind: rpkMailbox, sender: address)

func `==`*(a, b: ReversePath): bool =
  ## Structural equality across the two RFC 5321 Reverse-path arms. Auto-
  ## derived ``==`` on a case object fails with the parallel-fields-iterator
  ## compile error; this dispatches on the shared discriminator and compares
  ## only the fields valid for the matched arm. Mirrors ``SubmissionParam.==``.
  ##
  ## Nested case on both operands — strict doesn't carry ``a.kind ==
  ## b.kind`` across the outer branches.
  case a.kind
  of rpkNullPath:
    case b.kind
    of rpkNullPath:
      a.nullPathParams == b.nullPathParams
    of rpkMailbox:
      false
  of rpkMailbox:
    case b.kind
    of rpkNullPath:
      false
    of rpkMailbox:
      a.sender == b.sender

func `==`*(a, b: NonEmptyRcptList): bool {.borrow.}
  ## Element-wise equality delegated to the underlying seq.

func `$`*(a: NonEmptyRcptList): string {.borrow.}
  ## Textual form delegated to the underlying seq (diagnostic only).

func len*(a: NonEmptyRcptList): int {.borrow.}
  ## Recipient count; invariant ``>= 1`` by construction.

func `[]`*(a: NonEmptyRcptList, i: int): SubmissionAddress {.inline.} =
  ## Indexed access; explicit unwrap because ``{.borrow.}`` on ``[]``
  ## hits ``ArrGet`` (compiler magic).
  (seq[SubmissionAddress])(a)[i]

iterator items*(a: NonEmptyRcptList): SubmissionAddress =
  ## Forward iteration over recipients.
  for x in (seq[SubmissionAddress])(a):
    yield x

iterator pairs*(a: NonEmptyRcptList): (int, SubmissionAddress) =
  ## Forward iteration yielding ``(index, recipient)`` pairs.
  for i, x in (seq[SubmissionAddress])(a):
    yield (i, x)

func parseNonEmptyRcptList*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, seq[ValidationError]] =
  ## Strict client-side constructor (design §2.5 G7): rejects empty list
  ## AND duplicate recipients keyed on ``RFC5321Mailbox``. Accumulates
  ## every violation into one seq — mirrors ``parseSubmissionParams``.
  let errs = validateUniqueByIt(
    items, it.mailbox, "NonEmptyRcptList", "recipient list must not be empty",
    "duplicate recipient mailbox",
  )
  if errs.len > 0:
    return err(errs)
  ok(NonEmptyRcptList(@items))

func parseNonEmptyRcptListFromServer*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, ValidationError] =
  ## Lenient server-side constructor (design §2.5 G7, Postel's law):
  ## rejects only empty. Single ``ValidationError`` matches the
  ## ``parseIdFromServer`` / ``parseKeywordFromServer`` shape.
  if items.len == 0:
    return
      err(validationError("NonEmptyRcptList", "recipient list must not be empty", ""))
  ok(NonEmptyRcptList(@items))
