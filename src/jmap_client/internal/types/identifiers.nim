# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Semantically distinct identifier types built on Id validation rules. Separate
## from primitives.nim because these omit `len` — length is meaningless for
## opaque server tokens.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/[hashes, strutils]

import ./validation

type AccountId* = distinct string
  ## Server-assigned account identifier (RFC 8620 §2). Distinct from Id to
  ## prevent cross-use.

defineStringDistinctOps(AccountId)

type JmapState* = distinct string
  ## Opaque server state token for change tracking (RFC 8620 §5.3). No len
  ## borrow — length is meaningless.

func `==`*(a, b: JmapState): bool {.borrow.}
  ## Equality comparison delegated to the underlying string.
func `$`*(a: JmapState): string {.borrow.}
  ## String representation delegated to the underlying string.
func hash*(a: JmapState): Hash {.borrow.} ## Hash delegated to the underlying string.

type MethodCallId* = distinct string
  ## Client-assigned tag correlating requests with responses in a batch
  ## (RFC 8620 §3.2).

func `==`*(a, b: MethodCallId): bool {.borrow.}
  ## Equality comparison delegated to the underlying string.
func `$`*(a: MethodCallId): string {.borrow.}
  ## String representation delegated to the underlying string.
func hash*(a: MethodCallId): Hash {.borrow.} ## Hash delegated to the underlying string.

type CreationId* = distinct string
  ## Client-assigned temporary ID for back-references within a /set call
  ## (RFC 8620 §5.3). Wire format prefixes with '#'.

func `==`*(a, b: CreationId): bool {.borrow.}
  ## Equality comparison delegated to the underlying string.
func `$`*(a: CreationId): string {.borrow.}
  ## String representation delegated to the underlying string.
func hash*(a: CreationId): Hash {.borrow.} ## Hash delegated to the underlying string.

type BlobId* = distinct string
  ## Server-assigned opaque blob identifier (RFC 8620 §3.2). Follows the
  ## opaque-token borrow convention (JmapState/MethodCallId/CreationId):
  ## ==/$/hash only — no len borrow — forcing ``string(blobId).len`` at
  ## any call site that needs length, making opacity explicit.

func `==`*(a, b: BlobId): bool {.borrow.}
  ## Equality comparison delegated to the underlying string.
func `$`*(a: BlobId): string {.borrow.}
  ## String representation delegated to the underlying string.
func hash*(a: BlobId): Hash {.borrow.} ## Hash delegated to the underlying string.

type BuilderId* {.ruleOff: "objects".} = object
  ## Per-builder dispatch brand. Minted by ``JmapClient.newBuilder``;
  ## carried by every handle and by the ``DispatchedResponse`` returned
  ## from ``send``. Composite:
  ## - ``clientBrand`` identifies the issuing ``JmapClient`` (random,
  ##   64-bit; minted once at ``JmapClient`` construction via
  ##   ``std/sysrand.urandom``).
  ## - ``serial`` identifies the builder within that client (monotonic
  ##   ``uint64`` counter incremented inside ``JmapClient.newBuilder``).
  ## No wire form — internal-only.
  rawClientBrand: uint64
  rawSerial: uint64

func initBuilderId*(clientBrand, serial: uint64): BuilderId =
  ## Sole construction path for ``BuilderId``. Exported with ``*`` so
  ## internal callers (``client.nim``, builders, dispatch, tests under
  ## ``tests/``) can construct it, while ``types.nim`` filters this
  ## symbol from the hub re-export to keep it unreachable through
  ## ``import jmap_client``.
  BuilderId(rawClientBrand: clientBrand, rawSerial: serial)

func clientBrand*(b: BuilderId): uint64 =
  ## Diagnostic accessor — the ``clientBrand`` half of the composite.
  b.rawClientBrand

func serial*(b: BuilderId): uint64 =
  ## Diagnostic accessor — the ``serial`` half of the composite.
  b.rawSerial

func `==`*(a, b: BuilderId): bool =
  ## Structural equality across both halves.
  a.rawClientBrand == b.rawClientBrand and a.rawSerial == b.rawSerial

func hash*(a: BuilderId): Hash =
  ## Hash combining both halves via ``std/hashes`` ``!&`` / ``!$``
  ## mixer.
  !$(hash(a.rawClientBrand) !& hash(a.rawSerial))

func `$`*(a: BuilderId): string =
  ## Diagnostic textual form. Fixed layout — tests assert on the
  ## prefix.
  "BuilderId(brand=0x" & toHex(a.rawClientBrand.int64, 16) & ", serial=" & $a.rawSerial &
    ")"

func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2) —
  ## same lenient rules as parseIdFromServer.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "AccountId", raw))
  return ok(AccountId(raw))

func parseJmapState*(raw: string): Result[JmapState, ValidationError] =
  ## Non-empty, no control characters. Server-assigned — same defensive
  ## checks as other server-assigned identifiers.
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "JmapState", raw))
  return ok(JmapState(raw))

func parseMethodCallId*(raw: string): Result[MethodCallId, ValidationError] =
  ## Non-empty. Client-generated.
  detectNonEmpty(raw).isOkOr:
    return err(toValidationError(error, "MethodCallId", raw))
  return ok(MethodCallId(raw))

func parseCreationId*(raw: string): Result[CreationId, ValidationError] =
  ## Non-empty. Must not start with '#' (the prefix is a wire-format concern).
  detectNonEmptyNoPrefix(raw).isOkOr:
    return err(toValidationError(error, "CreationId", raw))
  return ok(CreationId(raw))

func parseBlobId*(raw: string): Result[BlobId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## Server-assigned — same lenient rules as parseIdFromServer.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "BlobId", raw))
  return ok(BlobId(raw))
