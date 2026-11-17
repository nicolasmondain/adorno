"""Per-command state, rebound by the commands: read and written as `ctx.X`, never imported by name (a
name bound at import would not see the change)."""

from __future__ import annotations

USE_LOCAL = False   # set per command: install/check/list/conf use local/, build never does
MODELS: dict = {}   # `models` of the repo being installed (local/adorno.yaml); empty for the public build
