# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## VacationResponse entity for RFC 8621 (JMAP Mail) section 7. A
## VacationResponse is a singleton object controlling automatic vacation
## replies. There is no ``id`` field on the Nim type — the singleton identity
## ("singleton") is handled purely in serialisation (Design Decision A6).

{.push raises: [], noSideEffect.}

import ../validation
import ../primitives

const VacationResponseSingletonId* = "singleton"
  ## The fixed identifier for the sole VacationResponse object (RFC 8621 §7).

type VacationResponse* {.ruleOff: "objects".} = object
  ## Server-side vacation auto-reply configuration (RFC 8621 section 7).
  ## All optional fields use ``Opt[T]`` — absent means the server decides.
  isEnabled*: bool ## Whether the vacation response is active.
  fromDate*: Opt[UTCDate] ## Start of the vacation window, or none.
  toDate*: Opt[UTCDate] ## End of the vacation window, or none.
  subject*: Opt[string] ## Subject line for the auto-reply, or none.
  textBody*: Opt[string] ## Plain-text body of the auto-reply, or none.
  htmlBody*: Opt[string] ## HTML body of the auto-reply, or none.

# =============================================================================
# VacationResponse Update Algebra
# =============================================================================

type VacationResponseUpdateVariantKind* = enum
  ## Discriminator for VacationResponseUpdate: names the settable RFC 8621
  ## §8 VacationResponse property being replaced. One variant per
  ## whole-value target — every VacationResponse property is replace-only,
  ## mirroring MailboxUpdate's structure.
  vruSetIsEnabled
  vruSetFromDate
  vruSetToDate
  vruSetSubject
  vruSetTextBody
  vruSetHtmlBody

type VacationResponseUpdate* {.ruleOff: "objects".} = object
  ## Single typed VacationResponse patch operation (RFC 8621 §8).
  ## Whole-value replace semantics — no sub-path targeting. Case object
  ## makes "exactly one target per update" a type-level fact, closing
  ## the empty-update and multi-property-update holes that a flat
  ## six-``Opt[T]`` record would leave open.
  case kind*: VacationResponseUpdateVariantKind
  of vruSetIsEnabled:
    isEnabled*: bool
  of vruSetFromDate:
    fromDate*: Opt[UTCDate] ## Opt.none clears the start date per RFC 8621 §8.
  of vruSetToDate:
    toDate*: Opt[UTCDate] ## Opt.none clears the end date per RFC 8621 §8.
  of vruSetSubject:
    subject*: Opt[string] ## Opt.none clears the subject per RFC 8621 §8.
  of vruSetTextBody:
    textBody*: Opt[string] ## Opt.none clears the text body per RFC 8621 §8.
  of vruSetHtmlBody:
    htmlBody*: Opt[string] ## Opt.none clears the HTML body per RFC 8621 §8.

func setIsEnabled*(isEnabled: bool): VacationResponseUpdate =
  ## Replace the VacationResponse's isEnabled flag.
  VacationResponseUpdate(kind: vruSetIsEnabled, isEnabled: isEnabled)

func setFromDate*(fromDate: Opt[UTCDate]): VacationResponseUpdate =
  ## Replace fromDate. Opt.none clears the start date per RFC 8621 §8.
  VacationResponseUpdate(kind: vruSetFromDate, fromDate: fromDate)

func setToDate*(toDate: Opt[UTCDate]): VacationResponseUpdate =
  ## Replace toDate. Opt.none clears the end date per RFC 8621 §8.
  VacationResponseUpdate(kind: vruSetToDate, toDate: toDate)

func setSubject*(subject: Opt[string]): VacationResponseUpdate =
  ## Replace subject. Opt.none clears the subject per RFC 8621 §8.
  VacationResponseUpdate(kind: vruSetSubject, subject: subject)

func setTextBody*(textBody: Opt[string]): VacationResponseUpdate =
  ## Replace textBody. Opt.none clears the text body per RFC 8621 §8.
  VacationResponseUpdate(kind: vruSetTextBody, textBody: textBody)

func setHtmlBody*(htmlBody: Opt[string]): VacationResponseUpdate =
  ## Replace htmlBody. Opt.none clears the HTML body per RFC 8621 §8.
  VacationResponseUpdate(kind: vruSetHtmlBody, htmlBody: htmlBody)

type VacationResponseUpdateSet* = distinct seq[VacationResponseUpdate]
  ## Validated, conflict-free batch of VacationResponseUpdate operations
  ## targeting the singleton VacationResponse. Construction gated by
  ## initVacationResponseUpdateSet — the raw distinct constructor is
  ## not part of the public surface.

func initVacationResponseUpdateSet*(
    updates: openArray[VacationResponseUpdate]
): Result[VacationResponseUpdateSet, seq[ValidationError]] =
  ## Accumulating smart constructor (Part F design §3.4). Rejects:
  ##   * empty input — the addVacationResponseSet `update` parameter has
  ##     exactly one "no updates" representation (omit the call entirely);
  ##   * duplicate target property — two updates with the same kind would
  ##     produce a JSON patch object with duplicate keys.
  ## All violations surface in a single Err pass; each repeated kind is
  ## reported exactly once regardless of occurrence count.
  let errs = validateUniqueByIt(
    updates,
    it.kind,
    typeName = "VacationResponseUpdateSet",
    emptyMsg = "must contain at least one update",
    dupMsg = "duplicate target property",
  )
  if errs.len > 0:
    return err(errs)
  ok(VacationResponseUpdateSet(@updates))
