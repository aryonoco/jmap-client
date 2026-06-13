# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## VacationResponse entity for RFC 8621 (JMAP Mail) section 8. A
## VacationResponse is a singleton object controlling automatic vacation
## replies. There is no ``id`` field on the Nim type — the singleton identity
## ("singleton") is handled purely in serialisation (Design Decision A6).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes

import ../types/validation
import ../types/primitives
import ../types/field_echo

const VacationResponseSingletonId* = "singleton"
  ## The fixed identifier for the sole VacationResponse object (RFC 8621 §8).

type VacationResponse* {.ruleOff: "objects".} = object
  ## Server-side vacation auto-reply configuration (RFC 8621 section 8).
  ## All optional fields use ``Opt[T]`` — absent means the server decides.
  isEnabled*: bool ## Whether the vacation response is active.
  fromDate*: Opt[UTCDate] ## Start of the vacation window, or none.
  toDate*: Opt[UTCDate] ## End of the vacation window, or none.
  subject*: Opt[string] ## Subject line for the auto-reply, or none.
  textBody*: Opt[string] ## Plain-text body of the auto-reply, or none.
  htmlBody*: Opt[string] ## HTML body of the auto-reply, or none.

# =============================================================================
# PartialVacationResponse
# =============================================================================

type PartialVacationResponse* {.ruleOff: "objects".} = object
  ## RFC 8621 §8 partial VacationResponse. Receive-only; produced by the
  ## library via ``SetResponse[NoCreate,
  ## PartialVacationResponse].updateResults`` (D6 — singleton-only ``/set``
  ## has no create rail) and ``GetResponse[PartialVacationResponse].list``
  ## (A4 + A3.6).
  isEnabled*: Opt[bool]
  fromDate*: FieldEcho[UTCDate] ## Wire admits null (clears start date per RFC 8621 §8).
  toDate*: FieldEcho[UTCDate] ## Wire admits null (clears end date).
  subject*: FieldEcho[string] ## Wire admits null (clears subject).
  textBody*: FieldEcho[string] ## Wire admits null (clears text body).
  htmlBody*: FieldEcho[string] ## Wire admits null (clears HTML body).

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

# =============================================================================
# Window-order invariant (RFC 8621 §8)
# =============================================================================

func fractionDigits(s: string): string =
  ## The RFC 8620 §1.4 ``time-secfrac`` digits between ``.`` and the trailing
  ## ``Z`` (empty when omitted). Relies on the validated ``UTCDate`` layout:
  ## a 19-char ``YYYY-MM-DDTHH:MM:SS`` prefix, then either ``Z`` or
  ## ``.<digits>Z``.
  if s.len <= 20 or s[19] != '.':
    return ""
  return s[20 ..< s.high]

func utcInstantLeq(a, b: UTCDate): bool =
  ## True iff ``a`` is at or before ``b`` on the UTC timeline. Sound for
  ## RFC 8620 §1.4 ``UTCDate``: the 19-char ``YYYY-MM-DDTHH:MM:SS`` prefix is
  ## fixed-width, zero-padded numerics with fixed separators (lexical order ==
  ## chronological); the optional fractional part is compared as a
  ## right-zero-padded digit string. Both values end in ``Z`` (the ``UTCDate``
  ## invariant), so no offset normalisation is needed.
  ##
  ## Module-private by design: the sealed ``UTCDate`` exposes no public
  ## ordering (it carries no calendar semantics). Naive ``string`` ``<`` is
  ## *unsound* here — ``"…01.5Z"`` would sort before ``"…01Z"`` because
  ## ``'.'`` < ``'Z'`` — which is precisely why this comparator splits the
  ## fixed prefix from the variable-precision fraction.
  let sa = $a
  let sb = $b
  if sa.len < 19 or sb.len < 19:
    # Defensive: a malformed value can only arrive via a future bug, never via
    # ``parseUtcDate``. Fall back to a total lexical order.
    return sa <= sb
  let prefixA = sa[0 ..< 19]
  let prefixB = sb[0 ..< 19]
  if prefixA != prefixB:
    return prefixA <= prefixB
  var fracA = fractionDigits(sa)
  var fracB = fractionDigits(sb)
  while fracA.len < fracB.len:
    fracA.add('0')
  while fracB.len < fracA.len:
    fracB.add('0')
  return fracA <= fracB

func windowOrderConflict(
    updates: openArray[VacationResponseUpdate]
): seq[ValidationError] =
  ## The locally-checkable subset of the RFC 8621 §8 window invariant: when a
  ## single batch sets BOTH endpoints to concrete dates and the start is
  ## strictly after the end, the window is empty/backwards. ``from == to`` is a
  ## degenerate (empty) window, not a contradiction, so it is permitted.
  ##
  ## Single-endpoint batches are intentionally unprotected: the server holds
  ## the other endpoint and is authoritative (it returns ``invalidProperties``
  ## if the combined window is illegal). Encoding only the honestly-enforceable
  ## subset is itself the P16 stance — do not pretend a guarantee the client
  ## cannot make.
  result = @[]
  var fromOpt = Opt.none(UTCDate)
  var toOpt = Opt.none(UTCDate)
  for u in updates:
    case u.kind
    of vruSetFromDate:
      for d in u.fromDate:
        fromOpt = Opt.some(d)
    of vruSetToDate:
      for d in u.toDate:
        toOpt = Opt.some(d)
    of vruSetIsEnabled, vruSetSubject, vruSetTextBody, vruSetHtmlBody:
      discard
  for f in fromOpt:
    for t in toOpt:
      if not utcInstantLeq(f, t):
        result.add(
          validationError(
            "VacationResponseUpdateSet",
            "window start is after window end",
            $f & " > " & $t,
          )
        )

type VacationResponseUpdateSet* {.ruleOff: "objects".} = object
  ## Validated, conflict-free batch of VacationResponseUpdate operations
  ## targeting the singleton VacationResponse. Sealed Pattern-A object —
  ## ``rawValue`` is module-private. Construction is gated by
  ## ``initVacationResponseUpdateSet``.
  rawValue: seq[VacationResponseUpdate]

func toSeq*(s: VacationResponseUpdateSet): seq[VacationResponseUpdate] {.inline.} =
  ## Value-projection accessor — returns a copy of the underlying seq.
  s.rawValue

func initVacationResponseUpdateSet*(
    updates: openArray[VacationResponseUpdate]
): Result[VacationResponseUpdateSet, seq[ValidationError]] =
  ## Accumulating smart constructor (Part F design §3.4). Rejects:
  ##   * empty input — the addVacationResponseSet `update` parameter has
  ##     exactly one "no updates" representation (omit the call entirely);
  ##   * duplicate target property — two updates with the same kind would
  ##     produce a JSON patch object with duplicate keys;
  ##   * a backwards window — a batch that sets BOTH ``fromDate`` and
  ##     ``toDate`` to concrete dates where the start is strictly after the end
  ##     (RFC 8621 §8; the locally-checkable subset of the window invariant, B4).
  ## All violations surface in a single Err pass; each repeated kind is
  ## reported exactly once regardless of occurrence count.
  let errs =
    validateUniqueByIt(
      updates,
      it.kind,
      typeName = "VacationResponseUpdateSet",
      emptyMsg = "must contain at least one update",
      dupMsg = "duplicate target property",
    ) & windowOrderConflict(updates)
  if errs.len > 0:
    return err(errs)
  ok(VacationResponseUpdateSet(rawValue: @updates))

# =============================================================================
# VacationResponseGetProperty — typed VacationResponse/get selector (A3.6)
# =============================================================================

type VacationResponseGetPropertyKind* = enum
  ## Discriminator for ``VacationResponseGetProperty``. Backing strings are
  ## the RFC 8621 §8 VacationResponse property wire names; ``vrgkOther``
  ## carries a capability-extension property whose raw identifier lives
  ## alongside.
  vrgkId = "id"
  vrgkIsEnabled = "isEnabled"
  vrgkFromDate = "fromDate"
  vrgkToDate = "toDate"
  vrgkSubject = "subject"
  vrgkTextBody = "textBody"
  vrgkHtmlBody = "htmlBody"
  vrgkOther

type VacationResponseGetProperty* {.ruleOff: "objects".} = object
  ## Typed RFC 8621 §8 VacationResponse/get property selector. Construction
  ## sealed; use the ``vrgp…`` constants or ``parseVacationResponseGetProperty``.
  case rawKind: VacationResponseGetPropertyKind
  of vrgkOther:
    rawIdentifier: string
  of vrgkId, vrgkIsEnabled, vrgkFromDate, vrgkToDate, vrgkSubject, vrgkTextBody,
      vrgkHtmlBody:
    discard

func kind*(p: VacationResponseGetProperty): VacationResponseGetPropertyKind =
  ## Returns the discriminator — one of the named arms or ``vrgkOther``.
  p.rawKind

func wireName*(p: VacationResponseGetProperty): string =
  ## RFC 8621 §8 wire name. For ``vrgkOther`` this is the captured identifier.
  case p.rawKind
  of vrgkOther:
    p.rawIdentifier
  of vrgkId, vrgkIsEnabled, vrgkFromDate, vrgkToDate, vrgkSubject, vrgkTextBody,
      vrgkHtmlBody:
    $p.rawKind

func `$`*(p: VacationResponseGetProperty): string =
  ## Wire-form string — equivalent to ``wireName``.
  p.wireName

func `==`*(a, b: VacationResponseGetProperty): bool =
  ## Wire-identity equality: the classifying parser never yields ``vrgkOther``
  ## for a known wire name, so wire-name identity is structural identity.
  a.wireName == b.wireName

func hash*(p: VacationResponseGetProperty): Hash =
  ## Consistent with ``==`` — equal wire names hash equal.
  hash(p.wireName)

const
  vrgpId* = VacationResponseGetProperty(rawKind: vrgkId) ## Selects ``id``.
  vrgpIsEnabled* = VacationResponseGetProperty(rawKind: vrgkIsEnabled)
    ## Selects ``isEnabled``.
  vrgpFromDate* = VacationResponseGetProperty(rawKind: vrgkFromDate)
    ## Selects ``fromDate``.
  vrgpToDate* = VacationResponseGetProperty(rawKind: vrgkToDate) ## Selects ``toDate``.
  vrgpSubject* = VacationResponseGetProperty(rawKind: vrgkSubject)
    ## Selects ``subject``.
  vrgpTextBody* = VacationResponseGetProperty(rawKind: vrgkTextBody)
    ## Selects ``textBody``.
  vrgpHtmlBody* = VacationResponseGetProperty(rawKind: vrgkHtmlBody)
    ## Selects ``htmlBody``.

func parseVacationResponseGetProperty*(
    raw: string
): Result[VacationResponseGetProperty, ValidationError] =
  ## Classifying smart constructor: exact, case-sensitive match against the
  ## RFC 8621 §8 wire names; unknown non-control strings fall to ``vrgkOther``
  ## (capability-extension forward-compat, A11).
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "VacationResponseGetProperty", raw))
  case raw
  of "id":
    ok(vrgpId)
  of "isEnabled":
    ok(vrgpIsEnabled)
  of "fromDate":
    ok(vrgpFromDate)
  of "toDate":
    ok(vrgpToDate)
  of "subject":
    ok(vrgpSubject)
  of "textBody":
    ok(vrgpTextBody)
  of "htmlBody":
    ok(vrgpHtmlBody)
  else:
    ok(VacationResponseGetProperty(rawKind: vrgkOther, rawIdentifier: raw))

defineSealedNonEmptySeqOps(VacationResponseGetProperty)
