# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit test for the S3 `limit` QueryParams helper (RFC 8620 §5.5).

{.push raises: [].}

import jmap_client/internal/types/framework
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation # re-exports nim-results (Opt/.get)

import ../massertions
import ../mtestblock

testCase limitSetsWindow:
  let qp = limit(parseUnsignedInt(20).get())
  assertSomeEq qp.limit, parseUnsignedInt(20).get()
