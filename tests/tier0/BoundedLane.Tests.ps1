#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Static wording pins for the bounded lane, plan-driven parallelism, and the read-less
# coordinator contract. The lane and parallelism apply to interactive mode only (no `mode=`)
# and are independent of the model routing mode. Each assertion quotes text shipped in
# squad-src; this proves the contract still reads the way it must, never that a model turn
# obeys it.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeDiscovery {
    # Rows with Flagged=$false must pass: a negated clause is exempt, but never a permission clause that follows it.
    $script:GuardCases = @(
        @{ Name = 'may edit directly'; Flagged = $true; Sentence = 'In the bounded lane the coordinator may edit the target file directly.' }
        @{ Name = 'yourself instead of dispatching'; Flagged = $true; Sentence = 'In the bounded lane, apply a one-line change yourself instead of dispatching.' }
        @{ Name = 'passive by the coordinator'; Flagged = $true; Sentence = 'For a bounded request the owning role''s work may be done by the coordinator.' }
        @{ Name = 'can author and skip review'; Flagged = $true; Sentence = 'In the bounded lane the coordinator can author the change and skip review.' }
        @{ Name = 'unqualified inline permission'; Flagged = $true; Sentence = 'For a fully specified one-line change you may apply it yourself.' }
        @{ Name = 'permitted to write'; Flagged = $true; Sentence = 'Within the lane, the coordinator is permitted to write the fix itself.' }
        @{ Name = 'permission after a negated clause'; Flagged = $true; Sentence = 'The bounded lane does not waive dispatch, but the coordinator may edit the file directly.' }
        @{ Name = 'subject-omitted modal after a negated clause'; Flagged = $true; Sentence = 'The lane does not waive dispatch, but may edit the file directly.' }
        @{ Name = 'safe negation then non-work verb (negative)'; Flagged = $false; Sentence = 'The coordinator does not waive dispatch, but may report the result.' }
        @{ Name = 'never edits (negative)'; Flagged = $false; Sentence = 'In the bounded lane the coordinator never edits the target file.' }
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
        param([Parameter(Mandatory)][string]$Body, [Parameter(Mandatory)][string]$Heading)
        $level = ($Heading -split ' ')[0].Length
        $pattern = '(?ms)^' + [regex]::Escape($Heading) + '\s*$.*?(?=^#{1,' + $level + '} |\z)'
        [regex]::Match($Body, $pattern).Value
    }

    function Get-Agent {
        param([Parameter(Mandatory)][string]$Name)
        @($script:Model.SquadAgents | Where-Object Name -eq $Name)[0]
    }

    $script:Coordinator = Get-Agent 'squad-coordinator.agent.md'
    $script:Floor = @($script:Model.Instructions | Where-Object Name -eq 'squad-floor.instructions.md')[0]
    $script:Routing = @($script:Model.Instructions | Where-Object Name -eq 'squad-routing.instructions.md')[0]
    $script:Gates = Get-SquadReferenceBody -Name 'gates-and-modes.md'
    $script:OperatingProcedure = Get-SquadReferenceBody -Name 'operating-procedure.md'
    $script:BoundedLane = Get-Section -Body $script:Gates -Heading '### Bounded Lane (Interactive Mode Only)'
}

Describe 'Bounded lane wording pins (RTE-38 to RTE-41)' {
    It 'requires every criterion to hold at once and states each one' {
        $script:BoundedLane | Should -Match ([regex]::Escape('only when **ALL** of these hold'))
        $script:BoundedLane | Should -Match ([regex]::Escape('names the exact target files or artifacts and the exact change'))
        $script:BoundedLane | Should -Match ([regex]::Escape('no open questions or unknowns'))
        $script:BoundedLane | Should -Match ([regex]::Escape('single owning role'))
        $script:BoundedLane | Should -Match ([regex]::Escape('disjoint write sets'))
        $script:BoundedLane | Should -Match ([regex]::Escape('No council domain is crossed'))
        $script:BoundedLane | Should -Match ([regex]::Escape('No Impactful-Action Gate or Risk Gate trigger applies'))
        $script:BoundedLane | Should -Match ([regex]::Escape('no intake or discovery gate trigger applies'))
    }

    It 'waives only Research and Plan: any doubt, pipeline=full, and autonomous or autopilot keep the full pipeline' {
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

    It 'is independent of model routing: no model pick, helper switch, or model id in the lane' {
        $script:BoundedLane | Should -Match ([regex]::Escape('The lane decides which stages run, never which model runs them.'))
        $script:BoundedLane | Should -Match ([regex]::Escape('keeps its normal model resolution under the active routing mode'))
        foreach ($text in $script:BoundedLane, $script:Coordinator.Body, $script:Routing.Body, $script:Floor.Body) {
            $text | Should -Not -Match '(?i)bounded (model )?pick'
            $text | Should -Not -Match ([regex]::Escape('-Bounded'))
            $text | Should -Not -Match '(?i)Pick Table'
        }
        $script:BoundedLane | Should -Not -Match '(?i)\b(gpt|claude|gemini|kimi)-[0-9a-z.-]+'
    }

    It 'the coordinator states the lane, pipeline=full, and defers the criteria to gates-and-modes' {
        $body = $script:Coordinator.Body
        $body | Should -Match ([regex]::Escape('* (Optional) `pipeline=full`'))
        $body | Should -Match ([regex]::Escape('except the **bounded lane** (interactive mode only; criteria in *Bounded Lane*)'))
        $body | Should -Match ([regex]::Escape('it waives Research and Plan only'))
        $body | Should -Match ([regex]::Escape('the owner is still dispatched, `tester` still closes, and the Scribe records `Route: bounded`'))
        $body | Should -Match ([regex]::Escape('Any doubt, or `pipeline=full`, means the full pipeline.'))
    }

    It 'the floor and routing instructions reconcile the methodology rule with the lane' {
        $script:Floor.Body | Should -Match ([regex]::Escape('with one exception: the **bounded lane**'))
        $script:Floor.Body | Should -Match ([regex]::Escape('It never waives dispatching the owning role or the closing `tester`.'))
        $script:Floor.Body | Should -Match ([regex]::Escape('skipped the methodology, unless the Scribe recorded `Route: bounded` with every bounded-lane criterion met'))
        $script:Routing.Body | Should -Match ([regex]::Escape('The one exception is the **bounded lane**'))
        $script:Routing.Body | Should -Match ([regex]::Escape('the owning role is still dispatched, never inline, `tester` still closes, and the Scribe records `Route: bounded`'))
    }

    It 'autopilot keeps every stage and the mode table does not imply the skipped stages must run' {
        $script:Gates | Should -Match ([regex]::Escape('Autopilot removes the human turn between stages; it does not remove the stages.'))
        $autopilot = @($script:Model.Instructions | Where-Object Name -eq 'squad-autopilot.instructions.md')[0]
        $autopilot.Body | Should -Match ([regex]::Escape('approves **each stage that runs**'))
        $autopilot.Body | Should -Match ([regex]::Escape('the bounded lane skips research and plan'))
    }

    It 'no always-on or hot text permits the coordinator to author, edit, or work inline (lexical guard)' {
        $texts = @($script:Coordinator.Body, $script:Floor.Body, $script:Routing.Body, $script:Gates, $script:OperatingProcedure)
        $offending = foreach ($text in $texts) { Find-InlineWorkPermission -Text $text }
        @($offending).Count | Should -Be 0 -Because "text must never let the coordinator work inline: $(@($offending) -join ' | ')"
    }

    It 'the guard flags <Name> and passes the negatives (lexical only)' -ForEach $script:GuardCases {
        $caught = @(Find-InlineWorkPermission -Text "The owning role is dispatched. $Sentence")
        ($caught.Count -gt 0) | Should -Be $Flagged -Because "'$Sentence' should $(if ($Flagged) { '' } else { 'not ' })be flagged; got: $($caught -join ' | ')"
    }
}

Describe 'Bounded owner brief (RTE-50)' {
    It 'names the write set, change, validation, and change record, allows a reference search, and returns blocked: not bounded' {
        $script:BoundedLane | Should -Match ([regex]::Escape('carries the exact target files (its full write set'))
        $script:BoundedLane | Should -Match ([regex]::Escape('the exact change, the validation command, the change-record path'))
        $script:BoundedLane | Should -Match ([regex]::Escape('you may search for references to any symbol, heading, or link you change'))
        $script:BoundedLane | Should -Match ([regex]::Escape('return "blocked: not bounded" without editing it'))
        $script:BoundedLane | Should -Match ([regex]::Escape('still follows the repository coding-standards instructions for every file it touches, still runs the validation, and still writes the change record last'))
        $script:BoundedLane | Should -Match ([regex]::Escape('apply the *Owner Finish Barrier* in `references/operating-procedure.md`'))
    }

    It 'the owner charters collapse the phase loop for a bounded dispatch but keep standards, validation, and output' {
        foreach ($name in 'squad-implementor.agent.md', 'squad-technical-writer.agent.md') {
            $body = (Get-Agent $name).Body
            $body | Should -Match ([regex]::Escape('For a `bounded` dispatch')) -Because $name
            $body | Should -Match ([regex]::Escape('do not explore the repository')) -Because $name
            $body | Should -Match ([regex]::Escape('return `blocked: not bounded` without editing it')) -Because $name
            $body | Should -Match ([regex]::Escape('The skill''s phase loop collapses to one phase.')) -Because $name
        }
    }
}

Describe 'Ordinary turns read less (RTE-50)' {
    It 'the coordinator runs the brief first and reads the references whole only when it does not cover the request' {
        $body = $script:Coordinator.Body
        $body | Should -Match ([regex]::Escape('run `scripts/Get-SquadDispatchBrief.ps1 -SquadRoot <root> -SessionModel <id>`'))
        $body | Should -Match ([regex]::Escape('when its `coverage:` line covers the request, it replaces every read below, agent files, and the rate table'))
        $body | Should -Match ([regex]::Escape('read these files whole (`view` `forceReadLargeFiles: true`)'))
    }

    It 'profiles-and-packs is read only for Init, a roster change, or a pack proposal, and each file once' {
        $body = $script:Coordinator.Body
        $body | Should -Match ([regex]::Escape('Read `references/seed-templates.md` and `references/profiles-and-packs.md` only for Init, a roster change, or a pack proposal.'))
        $body | Should -Match ([regex]::Escape('Read each file once; never re-read or grep it.'))
        $body | Should -Not -Match ([regex]::Escape('* `references/profiles-and-packs.md` —'))
    }

    It 'the coordinator body stays within the 30,000-character cap' {
        ($script:Coordinator.Body -replace "`r`n", "`n").Length | Should -BeLessOrEqual 30000
    }
}

Describe 'Plan-driven parallelism wording pins (RTE-21, RTE-23, RTE-24)' {
    BeforeAll {
        $script:Parallelism = Get-Section -Body $script:Gates -Heading '### Plan-Driven Parallelism (Interactive Mode Only)'
    }

    It 'applies to a deliverable-fan-out plan or a bounded request with disjoint write sets shown by it, never by budget' {
        $script:Parallelism | Should -Match ([regex]::Escape('`Implement Shape` is `deliverable-fan-out`'))
        $script:Parallelism | Should -Match ([regex]::Escape('a bounded request lists independent items'))
        $script:Parallelism | Should -Match ([regex]::Escape('their write sets are disjoint'))
        $script:Parallelism | Should -Match ([regex]::Escape('never inferred from budget'))
        $script:Parallelism | Should -Match ([regex]::Escape('When disjointness is unproven, dispatch sequentially'))
    }

    It 'confirms once per batch, never batches an escalate-tier owner, and leaves the Scribe rules unchanged' {
        $script:Parallelism | Should -Match ([regex]::Escape('confirmation once for the whole batch'))
        $script:Parallelism | Should -Match ([regex]::Escape('lists every owner, its tier, and its write set, and an `escalate`-tier owner is never batched'))
        $script:Parallelism | Should -Match ([regex]::Escape('Scribe single-writer, one hand-off per stage, and per-stage `history/<agent>.md` entries are unchanged'))
    }

    It 'the coordinator Step 3, the routing Dispatch Rules, and the operating procedure agree' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('in interactive mode only the owners of a `deliverable-fan-out` plan, or a bounded request''s independent items, run concurrently under one confirmation'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('(*Plan-Driven Parallelism*)'))
        $script:Routing.Body | Should -Match ([regex]::Escape('In interactive mode only (no `mode=`), owners may also run concurrently'))
        $script:Routing.Body | Should -Match ([regex]::Escape('shown by the plan or request and never by budget'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('In interactive mode only (no `mode=`), owners with plan- or request-proven disjoint write sets may also run concurrently'))
    }

    It 'RTE-24 states parallelism is interactive-only and autopilot uses its own fan-out' {
        $contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../squad-behavior-contract.md') -Raw
        $row = [regex]::Match($contract, '(?m)^\| RTE-24 \|.*$').Value
        $row | Should -Match ([regex]::Escape('interactive-only: under `mode=autonomous` it never applies, and `mode=autopilot` uses its own Implement fan-out'))
    }
}
