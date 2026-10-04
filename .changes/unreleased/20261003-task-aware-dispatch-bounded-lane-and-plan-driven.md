---
bump: patch
type: Changed
---

- **Every task paid for the full Research -> Plan pipeline, and independent deliverables ran one at a time.** In interactive mode only (not `mode=autonomous` or `mode=autopilot`), added a sanctioned bounded lane that waives Research and Plan only when every strict criterion holds (exact files and change named, no open questions, one owner or disjoint write sets, no council domain, no gate trigger); the owning role is still dispatched and reviewed, any doubt or `pipeline=full` keeps the full pipeline, and the Scribe records `Route: bounded`. A Lead plan with `deliverable-fan-out` (or a bounded request listing independent items) with disjoint write sets may now run its owners concurrently confirmed once per batch (the confirmation lists every owner, tier, and write set; an `escalate`-tier owner is never batched). See `squad-src/.github/agents/squad/squad-coordinator.agent.md`, `squad-src/.github/skills/squad/references/gates-and-modes.md`, `squad-src/.github/instructions/squad/squad-floor.instructions.md`, and `squad-src/.github/instructions/squad/squad-routing.instructions.md`.
