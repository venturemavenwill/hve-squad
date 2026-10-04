---
bump: patch
type: Fixed
---

- **The Scribe's ledger self-check failed on a hashtable it could not receive, `-SessionLog auto` took minutes on a machine with thousands of Copilot sessions, and the bounded lane never applied its cheaper model pick.** `Measure-SquadLedger.ps1 -ExpectedHistoryCounts` now also takes a string (`'Squad Implementor=2;Squad Scribe=1'`, comma separated, or a JSON object) that survives `pwsh -File`; duplicate names and blank strings exit 1. `-SessionLog auto` walks sessions newest first and stops at the first cwd match, trusting `COPILOT_AGENT_SESSION_ID` only when it is a GUID, a direct child of `session-state`, and that session's cwd is this repo; in one live run (run 3, 10,939 sessions) it dropped from 140.5 s to 7.7 s. The bounded lane now runs `Resolve-SquadModelRoute.ps1 -Bounded -Format compact` (or a pick table) before dispatching the owner, and the Scribe payload template names `priced_as` and the legal `model_source` values.
