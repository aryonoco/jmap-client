# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all Layer 1 modules. Import this single module to access
## the complete domain type vocabulary.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import results

import ./types/validation
import ./types/primitives
import ./types/identifiers
import ./types/collation
import ./types/submission_atoms
import ./types/capabilities
import ./types/account_capability_schemas
import ./types/methods_enum
import ./types/session
import ./types/envelope
import ./types/framework
import ./types/errors
import ./types/field_echo
import ./types/credential
import ./types/session_endpoint

export results
export validation except validationError, toValidationError
export primitives except parseFromString
export identifiers except initBuilderId
export collation
export submission_atoms
export capabilities except parseServerCapability, parseCoreCapabilities
export account_capability_schemas except
  parseAccountCapabilityEntry, parseMailAccountCapabilities,
  parseSubmissionAccountCapabilities
export methods_enum
export session except parseSession, parseAccount
export envelope except
  Invocation, Request, Response, ResultReference, ReferencableKind, methodCallId, name,
  arguments, rawName, initInvocation, parseInvocation, `using`, methodCalls, createdIds,
  initRequest, parseRequest, methodResponses, sessionState, initResponse, path, rawPath,
  resultOf, initResultReference, parseResultReference, kind, asDirect, asReference,
  referenceTo
export framework
export errors except
  requestError, methodError, setError, setErrorInvalidProperties, setErrorAlreadyExists,
  setErrorBlobNotFound, setErrorInvalidEmail, setErrorTooManyRecipients,
  setErrorInvalidRecipients, setErrorTooLarge
export field_echo
export credential except authorizationHeaderValue
export session_endpoint except asDirectUrl, asDiscoveryDomain
