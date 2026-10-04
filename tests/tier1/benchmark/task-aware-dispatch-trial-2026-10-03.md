# Task-aware dispatch live repeat: 2026-10-03

## Verdict

**FAIL: workflow acceptance.** The task artifacts pass their fixture tests, but
the coordinator performed the work inline, self-reviewed, and did not dispatch
roles or write squad history, state, or consumption. Do not treat the lower
runtime cost as a quality-preserving saving or claim live dispatch is fixed.

The preceding audit fixes passed focused deterministic checks: pre-hand-off
baselines, expected `###` entry counts plus requested entries and Scribe +1,
baseline timing, lexical mutation cases, and preservation of malformed custom
rate rows. Frontier sign-off covered these fixes, not live model compliance.

## Reproduction

This was a source-overlay smoke test, not a complete APM installation. hve-core
was not installed. The original E4 scratch fixture's baseline commit was
`99016ac7dc2c9bd7ad609d85aef64a06eab32b69`. The repeat used a new local clone
with its local remote removed and the current `squad-src` overlaid using
`Copy-SquadSource`. The harness did not repair the initial malformed rate file.

Copilot CLI: `1.0.92-3`. Session model: `claude-sonnet-5`. Agent:
`squad-coordinator`. Options matched E4: `--allow-all-tools`, `--no-ask-user`,
`--disable-builtin-mcps`, a 200-credit soft cap, JSON events and usage output,
and the original shell deny list. No global settings were changed. Auth-related
agent-host variables were removed only in the isolated launcher process to
use the installed CLI login, as in E4.

The unchanged prompt was:

> Three independent items, no dependencies between them: (1) implement: add a docstring to every function in src/ledger.py; (2) implement: add a test in tests/test_ledger.py that release() returns stock to the pool; (3) document: write docs/CONCURRENCY.md, one paragraph explaining the reserve() race described in the README. Then review all three. Route them through the squad as you normally would. Proceed without asking questions.

The no-questions wording does not authorize bypassing a required approval. A
compliant stop for a required approval would not be a completed delivery, but
would be preferable to silently performing prohibited inline work.

## Observed Result

| Check | Evidence | Result |
| --- | --- | --- |
| Process | Exit 0, 123 seconds | Not a workflow success signal |
| Usage | `totalNanoAiu=68220170000`; divide by `1e9` | 68.22017 runtime credits |
| Actual model | Only `main`, only `claude-sonnet-5`, 9 requests | No measured child-agent usage |
| Dispatch | 14 tool starts: glob 4, view 2, grep 2, edit 2, create 2, powershell 2; no task calls or child lifecycle events | FAIL |
| Artifact edits | Inline docstrings and test; new concurrency document | Present |
| Independent review | Coordinator explicitly self-reviewed; no reviewer dispatch | FAIL |
| Parallel role execution | No roles dispatched | FAIL |
| Squad state | No changes or new files under `.copilot-tracking` versus fixture HEAD | FAIL |
| Ledger and seeding scripts | Only mkdir and pytest shell commands; no squad scripts executed | FAIL / not exercised |
| Fixture tests | Logged 3 passed; independent audit rerun with bytecode/cache writes disabled also 3 passed | PASS |
| Loaded package | Metadata source hashes and installed coordinator/floor/routing matched current source | Verified by independent audit |

The coordinator stated it would "skip the full squad ceremony (multi-stage
dispatch + ledger scripts) and implement these three small, bounded items
directly, then self-review" because of the credit budget. This contradicts
the package's existing no-inline rule and bounded-lane owner/reviewer rules.

The original E4 runtime usage was 228.77 credits (rounded). It used child agents but
also had incomplete review/history after reaching its soft cap. Neither run
is a completed, equivalent-quality outcome suitable for a savings claim.

## Evidence Location

Raw local evidence is outside the repository because CLI logs can contain
machine/user context. These paths are local evidence pointers, not portable
fixtures or dependencies:

- `%TEMP%/hve-repeat-20261003-191208/out/metadata.json`: prompt, source hashes, runtime version and limitations.
- `%TEMP%/hve-repeat-20261003-191208/out/events.jsonl`: actual tool calls and final response.
- `%TEMP%/hve-repeat-20261003-191208/out/usage.json`: runtime usage and model/agent breakdown.
- `%TEMP%/hve-repeat-20261003-191208/out/result.json`: exit code and elapsed time.
- `%TEMP%/hve-fix/repeat-e4.ps1`: isolated repeat launcher.
- `%TEMP%/hve-fix/live-repeat-audit.md`: independent frontier audit, including fixture-test rerun.
- `%TEMP%/hve-fix/closure-signoff.md`: static/tool closure sign-off before this live run.

For example, read usage with `Get-Content <usage.json> -Raw | ConvertFrom-Json`
and count `tool.execution_start` records by `data.toolName` in the event stream.
The fixture's `git diff HEAD -- .copilot-tracking` is empty; also check untracked
paths so new history cannot be missed by a diff-only check.

## Interpretation And Next Gate

The transcript supports budget pressure as the coordinator's stated reason,
not a proven causal explanation. This is one warm-cache run with an incomplete
installation; runtime/version/environment differences prevent a controlled
comparison. Runtime credits are not reconciled billing.

Static wording and ledger-script tests do not enforce coordinator behavior.
The plugin's existing model dispatch guard applies to task calls and cannot
catch a run that never dispatches. It was not part of this source overlay.

Before claiming runtime closure, independently test an enforceable coordinator
write/dispatch boundary and stopping behavior when required work cannot fit the
budget. A higher or uncapped budget alone is not a repair. Further paid trials
and a broader enforcement implementation require separately agreed scope and
budget. No additional paid repeat was launched after this failure.

## Run 2: coordinator tool boundary

**Dispatch: PASS. Ledger: FAIL.** Same fixture, prompt, CLI version, model,
flags, and 200-credit cap, after the coordinator gained a `tools:` list with no
edit tools, the Cost Preflight script, and the budget-notice rule.

| Check | Result |
| --- | --- |
| Usage | 179.12686 runtime credits, 692 seconds, exit 0 |
| Coordinator tools | view 7, glob 5, grep 3, task 5; no edit, create, or shell call |
| Dispatch | Two Squad Implementors and Squad Technical Writer started together; Squad Reviewer, then Squad Scribe |
| Route | Coordinator reported `Route: bounded` |
| Review | Independent reviewer artifact under `.copilot-tracking/reviews/` |
| History and state | 5 `###` entries (Implementor 2, Writer 1, Reviewer 1, Scribe 1); `state.json` and `decisions.md` changed |
| Fixture tests | Rerun without bytecode or cache writes: 3 passed |
| Ledger | FAIL: no baseline, no `ledgerCommand`, and no squad script ran |

An independent `Measure-SquadLedger.ps1 -Check` reported 9 mismatches. The
hand-written `consumption.md` lacked the contract headings, Derivation
identities, and Total row. Its derived totals ($0.8185) disagreed with
`state.json` ($3.36). The malformed fixture rate file still fails the seeder's
`-Check`.

The tool boundary fixed the inline-work bypass in this run. It did not make the
coordinator run its shell-based ledger protocol. The remaining failure is in
the Scribe/ledger path. More prose alone is not expected to fix it.

## Runs 3-8: context, model choice, and deterministic hand-off

Same fixture, prompt, CLI, and session model; no credit cap (operator-authorized).
Each row is one live run; figures are host runtime usage, not reconciled billing.

| Run | Seconds | Credits | Owners (model, credits) | Hand-off | Fixture tests / review / ledger |
| --- | ---: | ---: | --- | --- | --- |
| 3 | 790 | 150 | Sonnet 5, 21.0 | Scribe, 458 s | pass / Pass / PASS |
| 4 | 924 | 134 | gpt-5.4-mini, 11.4; review began while owners still edited | Scribe, 358 s | pass / Pass / PASS |
| 5 | 727 | 154 | gpt-5.4-mini, 4.2 | script refused (roster header), Scribe 265 s | pass / Pass / PASS |
| 6 | 667 | 199 | gpt-5.4-mini, 10.8 | script after one retry; coordinator read the script | pass / Pass / PASS |
| 7 | 394 | 92 | gpt-5.4-mini, 9.1 | script after one retry, no Scribe dispatch | pass / Pass / PASS |
| 8 | 432 | 81 | gpt-5.4-mini, 6.6 | script after one retry, no Scribe dispatch | pass / Pass / PASS |
| 9 | 660 | 117 | Sonnet 5 pin, 25.0 (bounded pick skipped) | script after one retry, no Scribe dispatch | pass / Pass / PASS |
| 10 | 339 | 90 | gpt-5.4-mini, 8.3; Reviewer on its pin | script after one retry, no Scribe dispatch | pass / Pass / PASS |

Changes that produced the gains: closed `tools:` lists on spine charters (per-request
subagent input fell from roughly 90-126K to 20-25K tokens), the bounded-lane model
pick, an owner-finish barrier before review, and `Write-SquadHandoff.ps1` replacing
the ordinary Scribe hand-off. Dispatch, independent review, proof of dispatch, and the
single writer were kept in every run.

After run 8 the hand-off script gained a deterministic review-saw-final-files check
(replacing the optional quiesce snapshot), a warning when a bounded closing review or
owner ran on the wrong model, and a derived `priced_as`. Run 9 skipped the bounded pick
because the operative step lived only in a reference the coordinator skimmed; the step
now sits in the coordinator's bounded-lane rule, and run 10 applied it.

Open after run 10: the coordinator (session model) is 77-86% of credits; each run still
needed one payload retry. A single run per configuration is not a controlled comparison.