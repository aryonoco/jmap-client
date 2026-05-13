discard """
  action: "reject"
  errormsg: "the field 'rawValue' is not accessible."
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A8 reject — sealed types cannot be raw-constructed across module
## boundaries. ``AccountId`` is a sealed Pattern-A object with one
## module-private field ``rawValue``; attempting to set it from outside
## the defining module fails at compile time. The smart constructor
## ``parseAccountId`` is the only producer reachable here.

import jmap_client
discard AccountId(rawValue: "foo")
