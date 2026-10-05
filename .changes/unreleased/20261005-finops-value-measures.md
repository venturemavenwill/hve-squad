---
bump: minor
type: Added
---

- **FinOps value measures for the squad's own AI spend.** `Measure-SquadLedger.ps1` now writes a `## Unit Economics (value)` section into `consumption.md` on every hand-off (and a `unitEconomics` object with `-Format json`): deliverables produced, accepted by an independent review-class verdict, rejected and unreviewed; dispatches and rework dispatches; first-pass yield; estimated credits per accepted deliverable; rework and orchestration shares of estimated credits; and, when the host session is found, host-billed credits per accepted deliverable. Every figure carries a `measured`, `estimated` or `derived` label, and `-Check` ignores the section. The `Squad Cost Manager` gains an AI spend review mode that reads these figures, counts value only for accepted deliverables, compares medians of at least three like runs, flags a run above 1.5 times the comparable median, and ranks recommendations by credits saved per accepted deliverable, with pin, ceiling and roster changes at `confirm` tier. These follow the FinOps Foundation unit-economics and error-and-retry-waste KPIs.
