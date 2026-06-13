# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 6750 Bearer / RFC 7617 Basic client credential (Layer 1). Fully-sealed
## Pattern-A sum: the scheme is the module-private ``rawScheme`` discriminator
## (surfaced read-only via the ``scheme`` accessor), the secret material is a
## module-private payload, and the only producers are the smart constructors —
## so neither the payload nor a discriminator-only ``Credential(scheme: …)`` is
## constructible outside this module (A8b). The wire ``Authorization`` value is
## materialised at exactly one hub-private site (``authorizationHeaderValue``);
## ``$`` never renders the token or password.
##
## **Threading.** A ``Credential`` is an immutable value type — copy and share
## freely across threads.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/strutils

import ./validation

type AuthScheme* = enum
  ## RFC 7235 authentication scheme. The enum value is the wire scheme token;
  ## new schemes are additive variants (P20).
  asBearer = "Bearer"
  asBasic = "Basic"

type Credential* {.ruleOff: "objects".} = object
  ## Fully-sealed client credential. The discriminator is the module-private
  ## ``rawScheme`` field surfaced read-only via the ``scheme`` accessor, so
  ## both the secret payload AND ``Credential(scheme: …)`` discriminator-only
  ## construction are unreachable outside this module (A8b) — the only
  ## producers are ``bearerCredential`` / ``basicCredential``, and an
  ## empty-payload credential is structurally unrepresentable rather than
  ## inert-until-connect.
  case rawScheme: AuthScheme
  of asBearer:
    bearerTok: string
  of asBasic:
    basicUser, basicPass: string

func scheme*(c: Credential): AuthScheme =
  ## The authentication scheme (read-only view of the sealed ``rawScheme``
  ## discriminator). ``Credential(scheme: …)`` does not compile outside this
  ## module — A8b.
  c.rawScheme

type CredentialViolation = enum
  ## Structural-failure vocabulary for credential construction. Each variant
  ## maps to one wire message at ``toValidationError``.
  cvEmptyToken
  cvTokenControlChar
  cvEmptyUsername
  cvUsernameColon

func toValidationError(v: CredentialViolation): ValidationError =
  ## Sole domain-to-wire translator for ``CredentialViolation``. ``value`` is
  ## intentionally empty for every variant — credential material must never
  ## reach the error rail. Adding a variant forces a compile error here.
  case v
  of cvEmptyToken:
    validationError("Credential", "bearer token must not be empty", "")
  of cvTokenControlChar:
    validationError(
      "Credential", "bearer token must not contain control characters", ""
    )
  of cvEmptyUsername:
    validationError("Credential", "username must not be empty", "")
  of cvUsernameColon:
    validationError("Credential", "username must not contain ':'", "")

const Base64Alphabet =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  ## RFC 4648 §4 standard base64 alphabet.

func base64Char(sixBits: int): char =
  ## Maps a 6-bit group to its RFC 4648 §4 glyph. The mask keeps only the low
  ## six bits, so callers pass the raw shifted accumulator unmasked.
  Base64Alphabet[sixBits and 63]

func base64Encode(s: string): string =
  ## RFC 4648 §4 standard base64 with padding. Inlined rather than importing
  ## ``std/base64`` — ``base64.encode`` is a ``proc`` (side-effect-permitting)
  ## that would violate this module's ``{.push noSideEffect.}`` (decision #11).
  result = newStringOfCap(((s.len + 2) div 3) * 4)
  var i = 0
  while i < s.len:
    let remaining = s.len - i
    # Disjoint byte ranges — ``+`` packs the 24-bit group exactly as ``or``.
    let b1 =
      if remaining >= 2:
        ord(s[i + 1])
      else:
        0
    let b2 =
      if remaining >= 3:
        ord(s[i + 2])
      else:
        0
    let n = (ord(s[i]) shl 16) + (b1 shl 8) + b2
    result.add base64Char(n shr 18)
    result.add base64Char(n shr 12)
    result.add(
      if remaining >= 2:
        base64Char(n shr 6)
      else:
        '='
    )
    result.add(
      if remaining >= 3:
        base64Char(n)
      else:
        '='
    )
    i += 3

func bearerCredential*(token: string): Result[Credential, ValidationError] =
  ## RFC 6750 Bearer credential. Rejects an empty token or one containing
  ## control characters (the token is placed verbatim into the
  ## ``Authorization`` header, so control bytes would enable header injection).
  if token.len == 0:
    return err(toValidationError(cvEmptyToken))
  if token.contains({'\0' .. '\x1F', '\x7F'}):
    return err(toValidationError(cvTokenControlChar))
  ok(Credential(rawScheme: asBearer, bearerTok: token))

func basicCredential*(username, password: string): Result[Credential, ValidationError] =
  ## RFC 7617 Basic credential. The library owns the wire encoding —
  ## ``base64(username & ":" & password)`` is materialised only at
  ## ``authorizationHeaderValue``. RFC 7617 forbids ``:`` in the user-id; the
  ## password is unrestricted.
  if username.len == 0:
    return err(toValidationError(cvEmptyUsername))
  if username.contains(':'):
    return err(toValidationError(cvUsernameColon))
  ok(Credential(rawScheme: asBasic, basicUser: username, basicPass: password))

func `==`*(a, b: Credential): bool =
  ## Arm-dispatched structural equality (case objects require explicit ``==``
  ## under strict).
  case a.rawScheme
  of asBearer:
    case b.rawScheme
    of asBearer:
      a.bearerTok == b.bearerTok
    of asBasic:
      false
  of asBasic:
    case b.rawScheme
    of asBasic:
      a.basicUser == b.basicUser and a.basicPass == b.basicPass
    of asBearer:
      false

func `$`*(c: Credential): string =
  ## Redacted rendering. The token and password are NEVER printed; the Basic
  ## username is surfaced for debuggability (RFC 7617 user-id is not secret).
  case c.rawScheme
  of asBearer:
    "Credential(" & $c.rawScheme & ")"
  of asBasic:
    "Credential(" & $c.rawScheme & ", username: " & c.basicUser & ")"

func authorizationHeaderValue*(c: Credential): string =
  ## Hub-private (filtered at the Layer-1 re-export hub): the SOLE site the
  ## secret materialises into the wire ``Authorization`` value. ``$c.rawScheme``
  ## is the RFC scheme token.
  case c.rawScheme
  of asBearer:
    $c.rawScheme & " " & c.bearerTok
  of asBasic:
    $c.rawScheme & " " & base64Encode(c.basicUser & ":" & c.basicPass)
