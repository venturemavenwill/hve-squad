#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Static wording pins for the task-aware dispatch contract: the bounded lane, plan-driven
# parallelism, deterministic rate seeding, and ledger enforcement. The lane and parallelism
# apply to interactive mode only (no `mode=`): autonomous and autopilot never use them.
# Each assertion quotes text that is shipped in squad-src; this proves the contract still
# reads the way it must, never that a model turn obeys it.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeDiscovery {
    # Mutation inputs for the lexical guard (G1-G7 mirror the audit's mutation script). Flagged=$false
    # rows must pass: a negated clause is exempt, but never a permission clause that follows it.
    $script:GuardCases = @(
        @{ Name = 'G1 may edit directly'; Flagged = $true; Sentence = 'In the bounded lane the coordinator may edit the target file directly.' }
        @{ Name = 'G2 yourself instead of dispatching'; Flagged = $true; Sentence = 'In the bounded lane, apply a one-line change yourself instead of dispatching.' }
        @{ Name = 'G3 passive by the coordinator'; Flagged = $true; Sentence = 'For a bounded request the owning role''s work may be done by the coordinator.' }
        @{ Name = 'G4 can author and skip review'; Flagged = $true; Sentence = 'In the bounded lane the coordinator can author the change and skip review.' }
        @{ Name = 'G6 unqualified inline permission'; Flagged = $true; Sentence = 'For a fully specified one-line change you may apply it yourself.' }
        @{ Name = 'G7 permitted to write'; Flagged = $true; Sentence = 'Within the lane, the coordinator is permitted to write the fix itself.' }
        @{ Name = 'allowed to implement'; Flagged = $true; Sentence = 'The coordinator is allowed to implement a trivial fix.' }
        @{ Name = 'permission after a negated clause'; Flagged = $true; Sentence = 'The bounded lane does not waive dispatch, but the coordinator may edit the file directly.' }
        @{ Name = 'permission after a negated clause joined by and'; Flagged = $true; Sentence = 'The lane never waives the tester and you can apply the change yourself.' }
        @{ Name = 'CN2 subject-omitted modal after a negated clause'; Flagged = $true; Sentence = 'The lane does not waive dispatch, but may edit the file directly.' }
        @{ Name = 'CN3 never asks and may edit'; Flagged = $true; Sentence = 'The coordinator never asks for approval and may edit the target file directly.' }
        @{ Name = 'CN4 coordinator, not the owning role, may edit'; Flagged = $true; Sentence = 'The coordinator, not the owning role, may edit the target file directly.' }
        @{ Name = 'safe negation then non-work verb (negative)'; Flagged = $false; Sentence = 'The coordinator does not waive dispatch, but may report the result.' }
        @{ Name = 'safe negation then owner may edit (negative)'; Flagged = $false; Sentence = 'The coordinator never edits the file, and the owning role may edit it.' }
        @{ Name = 'may not edit (negative)'; Flagged = $false; Sentence = 'The coordinator does not dispatch inline, but may not edit the file itself.' }
        @{ Name = 'G5 does not waive dispatch (negative)'; Flagged = $false; Sentence = 'The bounded lane does not waive the dispatch of the owning role.' }
        @{ Name = 'never edits (negative)'; Flagged = $false; Sentence = 'In the bounded lane the coordinator never edits the target file.' }
        @{ Name = 'never author yourself (negative)'; Flagged = $false; Sentence = 'Never author the brief, framing, themes, or objections yourself.' }
        @{ Name = 'owner dispatched (negative)'; Flagged = $false; Sentence = 'The owning role is always dispatched, never inline, and tester still closes.' }
    )
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot

    function Find-InlineWorkPermission {
        <#
        .SYNOPSIS
            Lexical guard, not a proof of model behavior: returns clauses that grant the coordinator
            permission to do the owning role's work or to skip its dispatch.
        .DESCRIPTION
            Text is split into sentences and then clauses (at ; , : and/but/or). A clause is exempt
            only when a negation word precedes the match inside that same clause, so a permission
            that follows a negated clause ("does not waive dispatch, but may edit") is still flagged.
            A clause-initial modal ("..., but may edit") is flagged too, since the split drops its subject.
            Paraphrases the patterns do not name are not caught: this is a lexical check, not an
            exhaustive proof of policy.
        #>
        param([Parameter(Mandatory)][string]$Text)
        $verbs = 'author|edit|write|implement|apply|produce|perform|fix|patch|modify|do'
        $negation = "(?i)\b(never|not|no|nor|cannot|can't|don't|doesn't|won't|neither)\b"
        $patterns = @(
            "(?i)\b(coordinator|you)\s+(may|can|could|might|is permitted to|are permitted to|is allowed to|are allowed to|is free to|are free to)\s+(also\s+|still\s+|then\s+)?($verbs)\b"
            "(?i)\b(permitted|allowed|authori[sz]ed|free)\s+to\s+($verbs)\b"
            "(?i)\b($verbs)\b[^;:]{0,80}\byourself\b"
            "(?i)\b(done|authored|implemented|applied|performed|written|handled|made|fixed|edited)\s+(inline\s+)?by\s+the\s+coordinator\b"
            "(?i)\b(skip|skips|waive|waives|bypass|bypasses)\s+(the\s+)?(dispatch|dispatching|tester|review|owning role)"
            "(?i)\b(may|can)\s+(be\s+)?(done\s+|authored\s+|implemented\s+|applied\s+)?inline\b"
            "(?i)^\s*(?:(?:but|and|so|then)\s+)?(may|can|could|might|is permitted to|is allowed to)\s+(also\s+|still\s+|then\s+)?($verbs)\b"
        )
        foreach ($sentence in ($Text -split '(?<=[.!?])\s+|\r?\n')) {
            foreach ($clause in ($sentence -split '[;,:]\s+|\s+(?:and|but|or)\s+')) {
                foreach ($pattern in $patterns) {
                    $m = [regex]::Match($clause, $pattern)
                    if (-not $m.Success) { continue }
                    if ([regex]::IsMatch($clause.Substring(0, $m.Index + $m.Length), $negation)) { continue }
                    $clause.Trim()
                    break
                }
            }
        }
    }

    function Get-SquadReferenceBody {
        param([Parameter(Mandatory)][string]$Name)
        Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot "references/$Name") -Raw
    }

    function Get-Section {
        <#
        .SYNOPSIS
            Returns the text from a markdown heading line to the next heading of the same or higher level.
        #>
        param([Parameter(Mandatory)][string]$Body, [Parameter(Mandatory)][string]$Heading)
        $level = ($Heading -split ' ')[0].Length
        $pattern = '(?ms)^' + [regex]::Escape($Heading) + '\s*$.*?(?=^#{1,' + $level + '} |\z)'
        [regex]::Match($Body, $pattern).Value
    }

    $script:Coordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-coordinator.agent.md')[0]
    $script:Floor = @($script:Model.Instructions | Where-Object Name -eq 'squad-floor.instructions.md')[0]
    $script:Routing = @($script:Model.Instructions | Where-Object Name -eq 'squad-routing.instructions.md')[0]
    $script:Gates = Get-SquadReferenceBody -Name 'gates-and-modes.md'
    $script:ScribeProcedure = Get-SquadReferenceBody -Name 'scribe-procedure.md'
    $script:RatesTemplate = Get-SquadReferenceBody -Name 'consumption-rates-template.md'
    $script:ColdInit = Get-SquadReferenceBody -Name 'scribe-cold-init-and-seeding.md'
    $script:ColdFederation = Get-SquadReferenceBody -Name 'scribe-cold-federation.md'
    $script:OperatingProcedure = Get-SquadReferenceBody -Name 'operating-procedure.md'
}

Describe 'Bounded lane wording pins' {
    BeforeAll {
        $script:BoundedLane = Get-Section -Body $script:Gates -Heading '### Bounded Lane (Interactive Mode Only)'
    }

    It 'the Implementation Gate Procedure carries a Bounded Lane section' {
        $script:BoundedLane | Should -Not -BeNullOrEmpty
    }

    It 'requires every criterion to hold at once (conjunctive) and states each one' {
        $script:BoundedLane | Should -Match ([regex]::Escape('only when **ALL** of these hold'))
        $script:BoundedLane | Should -Match ([regex]::Escape('names the exact target files or artifacts and the exact change'))
        $script:BoundedLane | Should -Match ([regex]::Escape('no open questions or unknowns'))
        $script:BoundedLane | Should -Match ([regex]::Escape('single owning role'))
        $script:BoundedLane | Should -Match ([regex]::Escape('disjoint write sets'))
        $script:BoundedLane | Should -Match ([regex]::Escape('No council domain is crossed'))
        $script:BoundedLane | Should -Match ([regex]::Escape('No Impactful-Action Gate or Risk Gate trigger applies'))
        $script:BoundedLane | Should -Match ([regex]::Escape('no intake or discovery gate trigger applies'))
    }

    It 'waives only Research and Plan: any doubt, pipeline=full, and autopilot all keep the full pipeline' {
        $script:BoundedLane | Should -Match ([regex]::Escape('waives **only** those two stages'))
        $script:BoundedLane | Should -Match ([regex]::Escape('**Any doubt means the full pipeline.**'))
        $script:BoundedLane | Should -Match ([regex]::Escape('A `pipeline=full` input forces it'))
        $script:BoundedLane | Should -Match ([regex]::Escape('`mode=autonomous` and `mode=autopilot` never use the lane'))
    }

    It 'never lets the coordinator work inline and keeps review and Scribe recording' {
        $script:BoundedLane | Should -Match ([regex]::Escape('still dispatches the owning role through `runSubagent` or `task` — never inline'))
        $script:BoundedLane | Should -Match ([regex]::Escape('still dispatches `tester` as the closing stage'))
        $script:BoundedLane | Should -Match ([regex]::Escape('records `Route: bounded` and the criteria check'))
    }

    It 'the coordinator Implementation-gate bullet and Inputs list state the lane and pipeline=full' {
        $body = $script:Coordinator.Body
        $body | Should -Match ([regex]::Escape('* (Optional) `pipeline=full`'))
        $body | Should -Match ([regex]::Escape('except the **bounded lane** (interactive mode only, with no `mode=`'))
        $body | Should -Match ([regex]::Escape('it waives Research and Plan only'))
        $body | Should -Match ([regex]::Escape('Any doubt, or `pipeline=full`, means the full pipeline.'))
        $body | Should -Match ([regex]::Escape('The owning role is always dispatched, never inline; `tester` still closes'))
        $body | Should -Match ([regex]::Escape('`Route: bounded`'))
    }

    It 'the coordinator keeps its safety sentences and defers the full criteria list to gates-and-modes' {
        $body = $script:Coordinator.Body
        $body | Should -Match ([regex]::Escape('**Never author the brief, framing, themes, or objections yourself.**'))
        $body | Should -Match ([regex]::Escape('Never auto-seed `team.md` to avoid the build conversation.'))
        $body | Should -Match ([regex]::Escape('every criterion in *Bounded Lane*, `references/gates-and-modes.md`'))
    }

    It 'the floor reconciles the skipped-methodology rule with the lane' {
        $script:Floor.Body | Should -Match ([regex]::Escape('skipped the methodology, unless the Scribe recorded `Route: bounded` with every bounded-lane criterion met'))
        $script:Floor.Body | Should -Match ([regex]::Escape('in interactive mode only (no `mode=`)'))
    }

    It 'no always-on or hot text permits the coordinator to author, edit, or work inline (lexical guard, whole text)' {
        $texts = @($script:Coordinator.Body, $script:Floor.Body, $script:Routing.Body, $script:Gates, $script:OperatingProcedure)
        $offending = foreach ($text in $texts) { Find-InlineWorkPermission -Text $text }
        @($offending).Count | Should -Be 0 -Because "text must never let the coordinator work inline: $(@($offending) -join ' | ')"
    }

    It 'the guard flags <Name> and passes the negatives (table-driven, lexical only)' -ForEach $script:GuardCases {
        $caught = @(Find-InlineWorkPermission -Text "The owning role is dispatched. $Sentence")
        ($caught.Count -gt 0) | Should -Be $Flagged -Because "'$Sentence' should $(if ($Flagged) { '' } else { 'not ' })be flagged; got: $($caught -join ' | ')"
    }

    It 'the floor and routing instructions no longer contradict the lane' {
        $script:Floor.Body | Should -Match ([regex]::Escape('with one exception: the **bounded lane**'))
        $script:Floor.Body | Should -Match ([regex]::Escape('It never waives dispatching the owning role or the closing `tester`.'))
        $script:Routing.Body | Should -Match ([regex]::Escape('The one exception is the **bounded lane**'))
        $script:Routing.Body | Should -Match ([regex]::Escape('the owning role is still dispatched, never inline, `tester` still closes, and the Scribe records `Route: bounded`'))
    }

    It 'autopilot keeps its full pipeline: the Autopilot Procedure still requires every stage' {
        $script:Gates | Should -Match ([regex]::Escape('Autopilot removes the human turn between stages; it does not remove the stages.'))
    }

    It 'the mode table does not imply the bounded lane''s skipped stages must run' {
        $autopilot = @($script:Model.Instructions | Where-Object Name -eq 'squad-autopilot.instructions.md')[0]
        $autopilot.Body | Should -Match ([regex]::Escape('approves **each stage that runs**'))
        $autopilot.Body | Should -Match ([regex]::Escape('the bounded lane skips research and plan'))
    }

    It 'RTE-24 states parallelism is interactive-only, autonomous never applies it, and autopilot uses its own fan-out' {
        $contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../squad-behavior-contract.md') -Raw
        $row = [regex]::Match($contract, '(?m)^\| RTE-24 \|.*$').Value
        $row | Should -Match ([regex]::Escape('interactive-only: under `mode=autonomous` it never applies, and `mode=autopilot` uses its own Implement fan-out'))
        $row | Should -Not -Match ([regex]::Escape('the rule does not apply'))
    }
}

Describe 'Plan-driven parallelism wording pins (interactive mode only)' {
    BeforeAll {
        $script:Parallelism = Get-Section -Body $script:Gates -Heading '### Plan-Driven Parallelism (Interactive Mode Only)'
    }

    It 'gates-and-modes defines the section on a deliverable-fan-out plan or a bounded request' {
        $script:Parallelism | Should -Not -BeNullOrEmpty
        $script:Parallelism | Should -Match ([regex]::Escape('`Implement Shape` is `deliverable-fan-out`'))
        $script:Parallelism | Should -Match ([regex]::Escape('a bounded request lists independent items'))
    }

    It 'requires disjoint write sets shown by the plan or request, never by budget' {
        $script:Parallelism | Should -Match ([regex]::Escape('their write sets are disjoint'))
        $script:Parallelism | Should -Match ([regex]::Escape('never inferred from budget'))
        $script:Parallelism | Should -Match ([regex]::Escape('When disjointness is unproven, dispatch sequentially'))
    }

    It 'honors the confirmation tier once per batch and leaves Scribe rules unchanged' {
        $script:Parallelism | Should -Match ([regex]::Escape('confirmation once for the whole batch'))
        $script:Parallelism | Should -Match ([regex]::Escape('lists every owner, its tier, and its write set, and an `escalate`-tier owner is never batched'))
        $script:Parallelism | Should -Match ([regex]::Escape('Scribe single-writer, one hand-off per stage, and per-stage `history/<agent>.md` entries are unchanged'))
    }

    It 'the coordinator Step 3, the routing Dispatch Rules, and the operating procedure agree' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('in interactive mode only (no `mode=`) a Lead plan''s `deliverable-fan-out` shape'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('shown by that plan or request and never by budget'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('an `escalate`-tier owner is never batched'))
        $script:Routing.Body | Should -Match ([regex]::Escape('In interactive mode only (no `mode=`), owners may also run concurrently'))
        $script:Routing.Body | Should -Match ([regex]::Escape('shown by the plan or request and never by budget'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('In interactive mode only (no `mode=`), owners with plan- or request-proven disjoint write sets may also run concurrently'))
    }
}

Describe 'Deterministic rate seeding is wired into the Scribe procedure' {
    It 'the template, hot core, and both cold seeding files name the script and keep the verbatim fallback' {
        $script:RatesTemplate | Should -Match ([regex]::Escape('scripts/Initialize-SquadConsumptionRates.ps1 -SquadRoot <squadRoot>'))
        $script:RatesTemplate | Should -Match ([regex]::Escape('the verbatim copy described above is the fallback only when no shell or `pwsh` 7+ is available'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('scripts/Initialize-SquadConsumptionRates.ps1 -SquadRoot <squadRoot>'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('copy verbatim only without `pwsh`'))
        $script:ColdInit | Should -Match ([regex]::Escape('scripts/Initialize-SquadConsumptionRates.ps1 -SquadRoot <squadRoot>'))
        $script:ColdInit | Should -Match ([regex]::Escape('copy the template block verbatim only when no shell or `pwsh` 7+ is available'))
        $script:ColdFederation | Should -Match ([regex]::Escape('scripts/Initialize-SquadConsumptionRates.ps1 -SquadRoot <root>'))
    }

    It 'a malformed operator row is never deleted silently: the Scribe must surface the refusal and the drop note' {
        $script:RatesTemplate | Should -Match ([regex]::Escape('A malformed operator row is never deleted silently'))
        $script:RatesTemplate | Should -Match ([regex]::Escape('**surface that message in your confirmation**'))
        $script:RatesTemplate | Should -Match ([regex]::Escape('`Dropped malformed operator row` note you must also surface'))
        $script:ColdInit | Should -Match ([regex]::Escape('surface its message in the confirmation and leave the file as it is'))
    }

    It 'the seeding script ships beside Measure-SquadLedger.ps1' {
        Test-Path -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'scripts/Initialize-SquadConsumptionRates.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'scripts/Measure-SquadLedger.ps1') | Should -BeTrue
    }
}

Describe 'Coordinator tool boundary and budget fail-closed (RTE-42 to RTE-44)' {
    BeforeAll {
        $script:CoordinatorTools = @($script:Coordinator.Meta['tools'])
        $script:State = @($script:Model.Instructions | Where-Object Name -eq 'squad-state.instructions.md')[0]
        $script:Consumption = Get-SquadReferenceBody -Name 'consumption.md'
        $script:PreflightScript = 'scripts/Set-SquadCostPreflight.ps1'
    }

    It 'the coordinator frontmatter declares a tools list that keeps dispatch, shell, and read tools' {
        $script:CoordinatorTools.Count | Should -BeGreaterThan 0
        foreach ($tool in 'agent', 'task', 'execute', 'powershell', 'read', 'view', 'glob', 'grep') {
            $script:CoordinatorTools | Should -Contain $tool
        }
    }

    It 'the coordinator tools list is exactly the reviewed set, so any change is deliberate' {
        $expected = @('read', 'search', 'agent', 'execute', 'vscode/askQuestions', 'todo', 'view', 'glob', 'grep', 'task', 'powershell', 'bash', 'ask_user')
        $script:CoordinatorTools.Count | Should -Be $expected.Count
        @($script:CoordinatorTools | Sort-Object) | Should -Be @($expected | Sort-Object)
    }

    It 'the coordinator tools list grants no file-editing tool and no wildcard' {
        foreach ($tool in 'edit', 'create', 'apply_patch', 'str_replace_editor', 'editFiles', 'createFile', '*') {
            $script:CoordinatorTools | Should -Not -Contain $tool
        }
    }

    It 'the coordinator and the floor both state the budget fail-closed rule' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('A host budget notice (e.g. `<session_limits_status>`) never authorizes inline work, skipped or collapsed stages, self-review, or a skipped Scribe or ledger hand-off; it does not change the procedure: follow the stages in order and hand each to the Scribe as it returns, so the recorded state shows which stages ran.'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('Cost Preflight with a user `cost-ceiling` is the only admission gate.'))
        $script:Floor.Body | Should -Match ([regex]::Escape('A host session limit or budget notice (for example a `<session_limits_status>` message asking you to be frugal) never authorizes inline role work, skipped or collapsed stages, self-review, or a skipped Scribe or ledger hand-off.'))
        $script:Floor.Body | Should -Match ([regex]::Escape('Such a notice does not change the procedure: follow the stages in order, handing each stage to the Scribe as it returns, so that if the host limit is reached the recorded state shows exactly which stages ran.'))
        $script:Floor.Body | Should -Match ([regex]::Escape('report the risk once when the notice suggests the limit may not cover the required stages. Cost Preflight with a user `cost-ceiling` remains the only admission gate.'))
        $script:Floor.Body | Should -Not -Match ([regex]::Escape('stop before dispatch and report the shortfall'))
    }

    It 'the coordinator and the floor both forbid shell writes to squad state, deliverables, and source, and allow procedure-assigned steps' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('Never use the shell to create or modify squad state, deliverables, or source; it runs scripts, read-only inspection, and procedure-assigned steps (Watch Mode `git`/`gh`).'))
        $script:Floor.Body | Should -Match ([regex]::Escape('The coordinator never uses the shell to create or modify squad state files or any role''s deliverables or source changes. The shell runs the squad''s scripts, read-only inspection, and operations a procedure explicitly assigns to the coordinator (for example Watch Mode''s `git` and `gh` branch and draft-PR steps).'))
    }

    It 'every procedure doc routes the Cost Preflight transaction through Set-SquadCostPreflight.ps1' {
        foreach ($doc in $script:Coordinator.Body, $script:Floor.Body, $script:State.Body, $script:Gates, $script:Consumption) {
            $doc | Should -Match ([regex]::Escape('Set-SquadCostPreflight.ps1'))
        }
        $script:Gates | Should -Match ([regex]::Escape('The coordinator never edits these files by hand or through shell redirection.'))
        $script:Gates | Should -Match ([regex]::Escape('report `cannot-confirm` in chat, say to install PowerShell 7+ or pass `cost-ceiling=unset`, and dispatch nothing'))
    }

    It 'without pwsh a no-ceiling outcome resets through the Scribe, never a coordinator write' {
        $script:Gates | Should -Match ([regex]::Escape('hand the Scribe a payload with `costPreflightReset: not-requested` before any dispatch'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('a payload `costPreflightReset: not-requested` (no-`pwsh` reset) replaces `currentRun.costPreflight` with the exact `not-requested` object'))
        (Get-SquadReferenceBody -Name 'scribe-payload-template.md') | Should -Match 'costPreflightReset: <not-requested \| omit>'
    }

    It 'state docs no longer say the coordinator writes state, learnings, or the session model directly' {
        $script:OperatingProcedure | Should -Match ([regex]::Escape('the coordinator reads the shared playbook and hands local learnings to the Scribe'))
        $script:State.Body | Should -Match ([regex]::Escape('status document the Scribe overwrites as the squad advances'))
        $script:State.Body | Should -Match ([regex]::Escape('so it reports to the Scribe the model it is itself running on'))
        $script:Gates | Should -Match ([regex]::Escape('hands the answer to the Scribe to seed into `state.json` under `notify`'))
    }

    It 'no procedure doc still tells the coordinator to write the transaction directly' {
        $script:Gates | Should -Not -Match ([regex]::Escape('Directly append the Cost Preflight decision'))
        $script:Floor.Body | Should -Not -Match ([regex]::Escape('`currentRun.costPreflight`. When that transaction'))
    }

    It 'the preflight script ships with the squad skill' {
        Test-Path -LiteralPath (Join-Path $script:Model.SquadSkillRoot $script:PreflightScript) | Should -BeTrue
    }
}

Describe 'Ledger enforcement wording pins' {
    It 'the coordinator always supplies ledgerCommand with pwsh 7+ and verifies by read in Step 7, with the shell check additional' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('When `pwsh` 7+ is available, always supply `ledgerCommand`'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('emit the pre-hand-off baseline per *Hand-off Ledger Verification*'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('as an additional check'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('also run `Measure-SquadLedger.ps1 -SquadRoot <root> -Check -BaselinePath <baseline> -ExpectedHistoryCounts ''<history file>='))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('<pre-hand-off ### count + entries requested, Scribe +1>'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('never counts read back from the post-write listing'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('a non-zero exit is a failure'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('Skip only on an Init turn that dispatched no work.'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('Without `pwsh`, report the ledger as unverified.'))
    }

    It 'Step 7 verifies the ledger by reading consumption.md, re-dispatches the Scribe once, then reports failure (RTE-47)' {
        $body = $script:Coordinator.Body
        $body | Should -Match ([regex]::Escape('After every Scribe hand-off, with no shell needed, read `consumption.md`'))
        $body | Should -Match ([regex]::Escape('`### Derivation` block with `identities:` lines'))
        $body | Should -Match ([regex]::Escape('quotes `Measure-SquadLedger -Check: PASS`'))
        $body | Should -Match ([regex]::Escape('re-dispatch the Scribe once, telling it to run `Initialize-SquadConsumptionRates.ps1 -Check`, `Measure-SquadLedger.ps1 -Write -SessionLog auto`, then `-Check -ExpectedHistoryCounts`'))
        $body | Should -Match ([regex]::Escape('report the ledger as failed, never an exemption'))
        $body | Should -Match ([regex]::Escape('the Derivation is the single `unverified` marker and the response says `unverified`: report unverified, never re-dispatch'))
        $body | Should -Match ([regex]::Escape('a repair hand-off that adds one Scribe entry to the expected count and, under a ceiling, must fit the admitted round or the ledger is reported failed'))
        $body | Should -Match ([regex]::Escape('Under hand-off pipelining a failed read check is a failed verification (*Fail-closed and correction*), never a re-dispatch.'))
    }

    It 'the Scribe runs the seeding check and the ledger scripts whenever pwsh 7+ exists, never hand-writing consumption.md (RTE-47)' {
        $script:ScribeProcedure | Should -Match ([regex]::Escape('With `pwsh` 7+, whether or not the payload carries `ledgerCommand`, this entire step is the script run after Step 13; never edit `consumption.md` by hand.'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('With a shell tool and `pwsh` 7+, always write these rows with the tool, never by hand, and return its output lines in your response.'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('With `pwsh` 7+ always run `scripts/Initialize-SquadConsumptionRates.ps1 -SquadRoot <squadRoot> -Check` first'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('never `-DropMalformedRows` without operator approval'))
        $scribe = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-scribe.agent.md')[0]
        $scribe.Body | Should -Match ([regex]::Escape('always quote the `-Check` result line (`PASS`, or `unverified` without `pwsh`)'))
    }

    It 'the coordinator baseline is an additional check, never a precondition, in the operating procedure (RTE-47)' {
        $section = Get-Section -Body $script:OperatingProcedure -Heading '### Hand-off Ledger Verification (Every Hand-off)'
        $section | Should -Match ([regex]::Escape('an additional verification, never a precondition'))
        $section | Should -Match ([regex]::Escape('For a non-pipelined interactive or autonomous hand-off'))
        $section | Should -Match ([regex]::Escape('Hand-off pipelining keeps the baseline requirement below; without a coordinator shell and `pwsh` 7+, pipelining is disabled'))
        $section | Should -Match ([regex]::Escape('a missing coordinator baseline is not itself a failure'))
    }


    It 'the operating procedure fixes baseline and expected counts before the hand-off and treats a hand-off that skipped the ledger scripts as failure' {
        $section = Get-Section -Body $script:OperatingProcedure -Heading '### Hand-off Ledger Verification (Every Hand-off)'
        $section | Should -Not -BeNullOrEmpty
        $section | Should -Match ([regex]::Escape('-EmitBaseline <path outside the squad root>'))
        $section | Should -Match ([regex]::Escape('never while a Scribe call is in flight, so there is one writer and one baseline slot per squad root'))
        $section | Should -Match ([regex]::Escape('plus the entries this payload asks the Scribe to append to it; several entries for one agent each count'))
        $section | Should -Match ([regex]::Escape('-Check -BaselinePath <that baseline> -ExpectedHistoryCounts'))
        $section | Should -Match ([regex]::Escape('Under pipelining neither alone is verification.'))
        $section | Should -Match ([regex]::Escape('**A hand-off that did not run the ledger scripts with `pwsh` 7+ is a failure**, never an exemption'))
        $section | Should -Match ([regex]::Escape('a work hand-off on an Init turn may not'))
    }

    It 'the expected-count rule counts ### entries (not headingCount), adds Scribe +1 without double-counting, and emits the baseline immediately before each hand-off' {
        $section = Get-Section -Body $script:OperatingProcedure -Heading '### Hand-off Ledger Verification (Every Hand-off)'
        $section | Should -Match ([regex]::Escape('count its `###` entry headings by reading the file immediately before the hand-off'))
        $section | Should -Match ([regex]::Escape('not the baseline''s `headingCount`'))
        $section | Should -Not -Match ([regex]::Escape('the `headingCount` that baseline recorded'))
        $section | Should -Match ([regex]::Escape('`Squad Scribe` is also that count plus 1 per hand-off for its own orchestration entry, unless the payload already names an explicit Scribe entry (count it once, never twice)'))
        $section | Should -Match ([regex]::Escape('Emit it immediately before each Scribe hand-off, after that stage''s own role has returned and finished its edits'))
        $section | Should -Match ([regex]::Escape('let Role(N+1)''s outputs through `-AllowedWritePath`'))
        $section | Should -Not -Match ([regex]::Escape('Re-emit it after each verified hand-off'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('re-emitted immediately before each block)'))
    }

    It 'the floor no longer tells the writer to hand-write the Derivation block' {
        $script:Floor.Body | Should -Match ([regex]::Escape('never hand-write the block or an `identities:` line'))
        $script:Floor.Body | Should -Match ([regex]::Escape('the ledger is `unverified`'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('which only `-Write` writes; the unverified fallback leaves just its marker line'))
        $script:ScribeProcedure | Should -Not -Match ([regex]::Escape('Write the products into the file'))
    }

    It 'the Scribe never hand-writes the Derivation block or identities lines' {
        $script:ScribeProcedure | Should -Match ([regex]::Escape('**The Scribe never hand-writes the `### Derivation` block or any `identities:` line**'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('only `Measure-SquadLedger.ps1` writes them'))
        $script:ScribeProcedure | Should -Not -Match ([regex]::Escape('a hand-written Derivation must carry them all'))
    }

    It 'without the script the ledger is recorded as unverified, not fabricated' {
        $script:ScribeProcedure | Should -Match ([regex]::Escape('the ledger is then **unverified**'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('unverified — Measure-SquadLedger.ps1 did not run'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('report the ledger as unverified rather than running this guard'))
    }

    It 'keeps the host-agnostic fallback: the hand derivation still applies when pwsh 7+ is absent' {
        $script:ScribeProcedure | Should -Match ([regex]::Escape('Only when no shell tool or no `pwsh` 7+ is available does the manual derivation below apply'))
    }
}

Describe 'Spine charters carry a closed tools list (RTE-45)' {
    BeforeAll {
        $script:SpineTools = @('read', 'search', 'edit', 'execute', 'agent', 'web', 'todo', 'view', 'glob', 'grep', 'create', 'apply_patch', 'str_replace_editor', 'powershell', 'bash', 'task', 'skill', 'web_fetch')
        $script:ScribeTools = @('read', 'search', 'edit', 'execute', 'view', 'glob', 'grep', 'create', 'apply_patch', 'str_replace_editor', 'powershell', 'bash', 'skill', 'memory', 'vscode/memory', 'store_memory')
        $script:AgentNamed = { param($Name) @($script:Model.SquadAgents | Where-Object Name -eq $Name)[0] }
    }

    It '<Agent> declares exactly the reviewed tools list' -ForEach @(
        @{ Agent = 'squad-implementor.agent.md'; Kind = 'spine' }
        @{ Agent = 'squad-technical-writer.agent.md'; Kind = 'spine' }
        @{ Agent = 'squad-lead.agent.md'; Kind = 'spine' }
        @{ Agent = 'squad-reviewer.agent.md'; Kind = 'spine' }
        @{ Agent = 'squad-scribe.agent.md'; Kind = 'scribe' }
    ) {
        $tools = @((& $script:AgentNamed $Agent).Meta['tools'])
        $expected = if ($Kind -eq 'scribe') { $script:ScribeTools } else { $script:SpineTools }
        $tools.Count | Should -Be $expected.Count
        @($tools | Sort-Object) | Should -Be @($expected | Sort-Object)
        $tools | Should -Not -Contain '*'
    }

    It 'the Researcher, Federation Coordinator, and alternates stay unrestricted on purpose (the researcher needs MCP and web capabilities)' {
        foreach ($name in 'squad-researcher.agent.md', 'squad-federation-coordinator.agent.md', 'squad-challenger.agent.md') {
            (& $script:AgentNamed $name).Meta.Contains('tools') | Should -BeFalse -Because "$name is deliberately unrestricted"
        }
    }

}

Describe 'Bounded lane model pick and one escalation (RTE-46)' {
    BeforeAll {
        $script:RoutingRef = Get-SquadReferenceBody -Name 'model-routing.md'
        $script:BoundedLaneText = Get-Section -Body $script:Gates -Heading '### Bounded Lane (Interactive Mode Only)'
    }

    It 'the bounded lane passes the bounded pick only under routing off to implementation-class owners, never lowers tester, and prices the passed id' {
        $script:BoundedLaneText | Should -Match ([regex]::Escape('Only when routing is `off` (no `Model` column) and no user model override applies, pass each `implementation`-class owning role''s **bounded pick** as the dispatch `model`'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('Under `ranked` or `manual` the lane keeps the `Model` cell.'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('The Scribe and every non-`implementation` role keep normal resolution too.'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('a host or hook rejection or denial'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('The closing `tester` is never lowered.'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('Cost Preflight prices the passed id, not the pin.'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('`scripts/Resolve-SquadModelRoute.ps1 -Bounded`'))
    }

    It 'a Fail verdict, Critical or High finding, or blocked owner escalates once on the stronger of pin and ranked pick, then follows normal follow-through' {
        $script:BoundedLaneText | Should -Match ([regex]::Escape('returns a `Fail` verdict or any finding graded Critical or High, or the owner returns blocked or failed validation'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('re-dispatch that owner **once** on the stronger of its pin and its ranked pick at its real floor'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('A second failure follows *Review Follow-Through* with no further bounded retry.'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('`bounded pick: <id>`'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('`bounded escalation`'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('*Consequence Floors* still bind every non-bounded dispatch.'))
    }

    It 'model-routing defines the pick, its precedence exception, and bounded identity wording' {
        $script:RoutingRef | Should -Match '(?m)^## Bounded Lane Pick\s*$'
        $script:RoutingRef | Should -Match ([regex]::Escape('**Bounded lane exception.**'))
        $script:RoutingRef | Should -Match ([regex]::Escape('`routing=manual` always wins'))
        $script:RoutingRef | Should -Match ([regex]::Escape('`gpt-5.4-mini` (fit 2, Blended 0.300)'))
        $script:RoutingRef | Should -Match ([regex]::Escape('"bounded pick" / "bounded escalation"'))
        $script:RoutingRef | Should -Match ([regex]::Escape('never the pin it replaced'))
        $script:RoutingRef | Should -Match ([regex]::Escape('with routing `off`, an `implementation`-class owner''s dispatch passes its *Bounded Lane Pick*'))
        $script:RoutingRef | Should -Match ([regex]::Escape('How the hook treats a bounded dispatch is unverified live.'))
        $script:RoutingRef | Should -Match ([regex]::Escape('**stronger of its pin and its ranked pick at its real floor**'))
        $script:RoutingRef | Should -Match ([regex]::Escape('(*Bounded Lane Pick* is the one declared exception)'))
    }

    It 'the Bounded Lane section carries the operative step: run the helper in compact form before dispatch, or use the pick table' {
        $script:BoundedLaneText | Should -Match ([regex]::Escape('Do this before dispatching the owner, without reading `model-routing.md` or `model-catalog.md` (the helper and the Pick Table already embody them):'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('Resolve-SquadModelRoute.ps1 -Bounded -Format compact -SquadRoot <root> -AvailableModels'))
        $script:BoundedLaneText | Should -Match ([regex]::Escape('without a shell, use the *Bounded Lane Pick Table* below'))
    }

    It 'the precomputed Bounded Lane Pick Table equals what the helper computes from model-catalog.md on a roster with no Model column' {
        $row = [regex]::Match($script:BoundedLaneText, '(?m)^\| `implementation` \| `(?<pick>[^`]+)` \| `(?<f1>[^`]+)`, `(?<f2>[^`]+)` \| `(?<esc>[^`]+)` \|')
        $row.Success | Should -BeTrue -Because 'the table row must exist'

        $catalogPath = Join-Path $script:Model.SquadSkillRoot 'references/model-catalog.md'
        $retrieved = [regex]::Match((Get-Content -LiteralPath $catalogPath -Raw), '\*\*Retrieved:\s*(?<d>\d{4}-\d{2}-\d{2})\*\*').Groups['d'].Value
        $root = Join-Path $TestDrive 'bounded-table-root'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        @(
            'Model routing: off'
            ''
            '| Role | Member Name | Agent Name (Primary) | Alternate Agents | Selection Cue | Invocation | Model Tier | Deliverable Root |'
            '|------|-------------|----------------------|------------------|---------------|------------|------------|------------------|'
            '| developer | Beta | Squad Implementor | — | d | task | default | src/ |'
        ) | Set-Content -LiteralPath (Join-Path $root 'team.md')

        $helper = Join-Path $script:Model.SquadSkillRoot 'scripts/Resolve-SquadModelRoute.ps1'
        $json = & pwsh -NoProfile -File $helper -SquadRoot $root -Bounded -AsOf $retrieved -Format json | Out-String | ConvertFrom-Json
        $dev = $json.roles | Where-Object { $_.role -eq 'developer' }
        $dev.boundedPick | Should -Be $row.Groups['pick'].Value
        @($dev.boundedFallbacks) | Should -Be @($row.Groups['f1'].Value, $row.Groups['f2'].Value)
        $dev.boundedEscalation | Should -Be $row.Groups['esc'].Value -Because 'the Pick Table escalation column equals the helper at the default floor'

        $compact = & pwsh -NoProfile -File $helper -SquadRoot $root -Bounded -AsOf $retrieved -Format compact
        ($compact | Where-Object { $_ -like 'developer:*' }) | Should -Be "developer: $($row.Groups['pick'].Value) (then $($row.Groups['f1'].Value), $($row.Groups['f2'].Value); escalate: $($row.Groups['esc'].Value))"
    }

    It 'the compact bounded output names the stronger of the agent pin and the ranked pick as the escalation target' {
        $repo = Join-Path $TestDrive 'escalate-repo'
        $squad = Join-Path $repo '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path $squad, (Join-Path $repo '.github/agents') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo '.github/agents/pinned.agent.md') -Value "---`nname: Pinned Implementor`nmodel: Claude Sonnet 5.5 (copilot)`n---`n"
        @(
            'Model routing: off'
            ''
            '| Role | Member Name | Agent Name (Primary) | Alternate Agents | Selection Cue | Invocation | Model Tier | Deliverable Root |'
            '|------|-------------|----------------------|------------------|---------------|------------|------------|------------------|'
            '| developer | Beta | Pinned Implementor | — | d | task | default | src/ |'
        ) | Set-Content -LiteralPath (Join-Path $squad 'team.md')
        $helper = Join-Path $script:Model.SquadSkillRoot 'scripts/Resolve-SquadModelRoute.ps1'
        $json = & pwsh -NoProfile -File $helper -SquadRoot $squad -Bounded -Format json | Out-String | ConvertFrom-Json
        $dev = $json.roles | Where-Object { $_.role -eq 'developer' }
        $dev.boundedEscalation | Should -Not -BeNullOrEmpty
        $compact = & pwsh -NoProfile -File $helper -SquadRoot $squad -Bounded -Format compact
        ($compact | Where-Object { $_ -like 'developer:*' }) | Should -Match ([regex]::Escape("escalate: $($dev.boundedEscalation))"))
    }

    It 'the coordinator and routing instructions point at the pick without restating the algorithm' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('under routing `off` only, pass each `implementation`-class owner its bounded pick as `model` (never under `ranked`, `manual`, or a user override)'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('on a `Fail` verdict, a Critical or High finding, a blocked owner, or failed validation re-dispatch that owner once on the stronger of its pin and its ranked pick at its real floor'))
        $script:Routing.Body | Should -Match ([regex]::Escape('its bounded model pick (*Bounded Lane Pick* in `references/model-routing.md`)'))
    }

    It 'the coordinator reads the routing references only for active routing, never for a bounded pick, and keeps the turn lean' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('a `routing=` input or a `Model routing:` line in `team.md` reads `references/model-routing.md` and `references/model-catalog.md` too (a bounded pick uses the helper or Pick Table instead)'))
        $script:Coordinator.Body | Should -Not -Match ([regex]::Escape('or a bounded-lane dispatch reads'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('Keep this turn lean'))
    }
}

Describe 'Deterministic hand-off and fast-path wording pins' {
    It 'every procedure doc states the same script hand-off sentence: ordinary payloads by script, the rest to the Scribe' {
        $sentence = 'an ordinary hand-off (history, decision, orchestration, state advance) is written by `scripts/Write-SquadHandoff.ps1`'
        foreach ($doc in $script:Coordinator.Body, $script:Floor.Body, $script:State.Body, $script:OperatingProcedure) {
            $doc | Should -Match ([regex]::Escape($sentence))
            $doc | Should -Match ([regex]::Escape('payload types it does not cover, a script refusal, or no `pwsh` go to the Squad Scribe'))
        }
        $script:Coordinator.Body | Should -Match ([regex]::Escape('run by the coordinator as the single writer for that hand-off (no Scribe in flight)'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('A memory note, ADR flag, or learning goes to the Scribe as a memory payload.'))
    }

    It 'the script hand-off never overlaps a Scribe hand-off or a role dispatch' {
        $script:OperatingProcedure | Should -Match ([regex]::Escape('Never run the script while a Scribe hand-off for the same squad root is in flight, run it only after any earlier Scribe hand-off for that root returned with its quoted `-Check: PASS`, and never in the same tool-call block as a role dispatch'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('Pass the payload in-process as a single-quoted here-string so `$` and backticks survive'))
        $script:ScribeProcedure | Should -Match ([regex]::Escape('never concurrently with a Scribe hand-off for the same root'))
        $script:Floor.Body | Should -Match ([regex]::Escape('never a Scribe hand-off and the script together for one squad root, and never a hand edit of these files'))
    }

    It 'the shell rule is unchanged and names the script as a script run, and Step 7 takes the script PASS line as ledger evidence' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('Running `scripts/Write-SquadHandoff.ps1` is that script run, not a shell write.'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('its `Measure-SquadLedger -Check: PASS` line is the ledger evidence; no Scribe repair runs'))
    }

    It 'the owner finish barrier gates the closing review on change records and the hand-off script''s review-saw-final-files check' {
        $script:OperatingProcedure | Should -Match ([regex]::Escape('An owner''s `task` return is not proof it finished'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('No payload edit fixes that refusal: re-dispatch the review on the final files, then rerun the script'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('This check replaces the quiesce snapshot on the ordinary path'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('-WaitStable 20 -MaxWaitSeconds 600'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('re-dispatch the review, never edit the payload'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('ending with a `Status: complete'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('dispatch no review until every owner is finished'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('or a change record without `Status: complete`, is unfinished'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('apply the *Owner Finish Barrier* in `references/operating-procedure.md`'))
        $script:Gates | Should -Match ([regex]::Escape('apply the *Owner Finish Barrier* in `references/operating-procedure.md`'))
    }

    It 'the bounded owner brief names files, change, validation, change record, and the no-exploration line without dropping standards or the change record' {
        $script:Gates | Should -Match ([regex]::Escape('carries the exact target files (its full write set'))
        $script:Gates | Should -Match ([regex]::Escape('the exact change, the validation command, the change-record path'))
        $script:Gates | Should -Match ([regex]::Escape('return "blocked: not bounded" without editing it'))
        $script:Gates | Should -Match ([regex]::Escape('do not explore the repository'))
        $script:Gates | Should -Match ([regex]::Escape('still follows the repository coding-standards instructions for every file it touches, still runs the validation, and still writes the change record'))
    }

    It 'ordinary turns read profiles-and-packs only for Init, a roster change, or a pack proposal, and each file once' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('Read `references/seed-templates.md` and `references/profiles-and-packs.md` only for Init, a roster change, or a pack proposal.'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('Read each file once, in one parallel block; never re-read or grep a file already read this turn.'))
        $script:Coordinator.Body | Should -Not -Match ([regex]::Escape('* `references/profiles-and-packs.md` —'))
    }

    It 'the owners declare the finish barrier: one final message, no announced next steps' {
        foreach ($name in 'squad-implementor.agent.md', 'squad-technical-writer.agent.md', 'squad-lead.agent.md', 'squad-reviewer.agent.md') {
            $agent = @($script:Model.SquadAgents | Where-Object Name -eq $name)[0]
            $agent.Body | Should -Match ([regex]::Escape('Send no text-only message until every edit, validation command, and the')) -Because $name
            $agent.Body | Should -Match ([regex]::Escape('are finished; your single final message is the report.')) -Because $name
            $agent.Body | Should -Match ([regex]::Escape('last, ending with `Status: complete')) -Because $name
            $agent.Body | Should -Match ([regex]::Escape('Never announce what you will do next in a final message.')) -Because $name
        }
        $scribe = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-scribe.agent.md')[0]
        $scribe.Body | Should -Match ([regex]::Escape('Send no text-only message until every write and the ledger check are done; your one final message is the confirmation.'))
    }

    It 'no always-on or charter text still claims the Scribe is the only writer without naming the script' {
        $source = Join-Path $PSScriptRoot '../../squad-src/.github'
        $banned = @(
            'this is the sole exception to Scribe-owned writes',
            'every mutation funnels through the scribe',
            'Because only the Scribe writes history',
            'the Scribe has written the matching history entry',
            'is the sole writer of squad state',
            'Only the Squad Scribe writes history.',
            'the owning coordinator may directly perform only Cost Preflight.'
        )
        $hits = foreach ($file in (Get-ChildItem -LiteralPath $source -Recurse -File -Include '*.md')) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($phrase in $banned) { if ($text.Contains($phrase)) { "$($file.Name): $phrase" } }
        }
        @($hits) | Should -BeNullOrEmpty -Because 'the single writer for an ordinary hand-off is the Scribe or Write-SquadHandoff.ps1, never both'
    }

    It 'the bounded dispatch collapses the owner skill phase loop and skips exploration but keeps standards, validation, and the change record' {
        foreach ($name in 'squad-implementor.agent.md', 'squad-technical-writer.agent.md') {
            $agent = @($script:Model.SquadAgents | Where-Object Name -eq $name)[0]
            $agent.Body | Should -Match ([regex]::Escape('For a `bounded` dispatch')) -Because $name
            $agent.Body | Should -Match ([regex]::Escape('do not explore the repository')) -Because $name
        }
    }
}