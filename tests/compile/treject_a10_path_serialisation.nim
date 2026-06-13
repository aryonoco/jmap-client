discard """
  action: "reject"
  errormsg: "cannot open file: jmap_client/serialisation"
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A10 reject — ``import jmap_client/serialisation`` must fail to
## compile after A10. The closed-set public-path lock demotes
## every sub-path under ``jmap_client/`` except
## ``jmap_client/convenience`` to internal; consumers reach the
## API exclusively through ``import jmap_client``.

import jmap_client/serialisation
