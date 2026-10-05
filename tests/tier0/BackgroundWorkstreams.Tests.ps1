#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Static wording pins for background workstreams (`delivery=background`, interactive mode only)
# and the Squad Workstream Lead. Each assertion quotes text shipped in squad-src; this proves
# the contract still reads the way it must, never that a model turn obeys it. The hand-off
# script's workstream fields are exercised in WriteSquadHandoff.Tests.ps1.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

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
    $script:Lead = Get-Agent 'squad-workstream-lead.agent.md'
    $script:Gates = Get-SquadReferenceBody -Name 'gates-and-modes.md'
    $script:BgText = Get-Section -Body $script:Gates -Heading '## Background Workstreams Procedure (Interactive Mode Only)'
    $script:Parallelism = Get-Section -Body $script:Gates -Heading '### Plan-Driven Parallelism (Interactive Mode Only)'
}

Describe 'Squad Workstream Lead charter (RTE-51)' {
    It 'exists, is not user-invocable, carries the Squad Lead''s pin, and declares no tools so its children keep their own' {
        $script:Lead | Should -Not -BeNullOrEmpty
        $script:Lead.Meta['name'] | Should -Be 'Squad Workstream Lead'
        $script:Lead.Meta['user-invocable'] | Should -Be 'false'
        $script:Lead.Meta.ContainsKey('tools') | Should -BeFalse
        $script:Lead.Meta['model'] | Should -Be (Get-Agent 'squad-lead.agent.md').Meta['model']
        @($script:Lead.Meta['agents']) | Should -Not -Contain 'Squad Scribe'
        @($script:Lead.Meta['agents']) | Should -Not -Contain 'Squad Deployer'
        $script:Lead.Body.Length | Should -BeLessOrEqual 30000
    }

    It 'can dispatch every tester alternate, QA, and the producing roles, each also known to the coordinator' {
        $catalog = Get-SquadReferenceBody -Name 'roster-catalog.md'
        $testerRow = @($catalog -split "`n" | Where-Object { $_ -match '^\| tester ' -and $_ -match 'Code Review Walkback' })[0]
        $alternates = @((($testerRow -split '\|') | Where-Object { $_ -match 'Code Review Functional' })[0].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $alternates.Count | Should -BeGreaterOrEqual 7
        $leadAgents = @($script:Lead.Meta['agents'])
        foreach ($name in $alternates + @('QA', 'Squad Implementor', 'Squad Reviewer', 'Squad Technical Writer', 'Squad Data Scientist')) { $leadAgents | Should -Contain $name }
        foreach ($name in $leadAgents) { @($script:Coordinator.Meta['agents']) | Should -Contain $name }
    }

    It 'forwards briefs verbatim, sends one final message, writes no squad state, and never works inline' {
        $script:Lead.Body | Should -Match ([regex]::Escape('Forward each owner''s brief to that owner VERBATIM.'))
        $script:Lead.Body | Should -Match ([regex]::Escape('your single final message is the report'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Never write squad state: no `history/`, `decisions.md`, `state.json`, `consumption.md`, `team.md`, or Scribe file, and never run `Write-SquadHandoff.ps1` or dispatch the Squad Scribe.'))
        $script:Lead.Body | Should -Match ([regex]::Escape('the coordinator hands your workstream''s payload to the Squad Scribe, the only writer, which runs the script'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Never do role work inline.'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Never perform an impactful action'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Apply the *Owner Finish Barrier*'))
        $script:Lead.Body | Should -Match ([regex]::Escape('by the reviewer agent the coordinator named in your brief'))
        @(Find-InlineWorkPermission -Text $script:Lead.Body) | Should -BeNullOrEmpty
    }

    It 'copies each owner''s Model cell as written under any routing mode that writes it, and never picks a model' {
        $script:Lead.Body | Should -Match ([regex]::Escape('Under `ranked`, `manual`, or any routing mode that writes the `Model` cell, pass that cell as the dispatch `model` for that owner and for the closing reviewer, as the coordinator does'))
        $script:Lead.Body | Should -Match ([regex]::Escape('with no cell value, pass no `model`, so the agent runs on its own pin'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Never pick, rank, or lower a model yourself'))
        $script:Lead.Body | Should -Not -Match '(?i)bounded pick|boundedPick|(?<![a-z])-Bounded\b'
        $script:Lead.Body | Should -Not -Match '(?i)\b(claude|gpt-|gemini|grok)'
    }
}

Describe 'Coordinator entry points for background workstreams (RTE-51)' {
    It 'lists the lead, declares the delivery input, runs the brief with -Background, and waits with read_agent' {
        @($script:Coordinator.Meta['agents']) | Should -Contain 'Squad Workstream Lead'
        $script:Coordinator.Body | Should -Match ([regex]::Escape('* (Optional) `delivery=background` — interactive only: disjoint workstreams run in background per *Background Workstreams Procedure* (`references/gates-and-modes.md`).'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('(`-Background` with `delivery=background`)'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('wait for it (Copilot CLI: `read_agent` `wait: true`)'))
        $script:Coordinator.Body.Length | Should -BeLessOrEqual 30000
    }

    It 'holds read_agent whenever it declares a tools list' {
        if ($script:Coordinator.Meta.ContainsKey('tools')) { @($script:Coordinator.Meta['tools']) | Should -Contain 'read_agent' }
    }

    It 'the /squad prompt declares delivery=background' {
        @($script:Model.Prompts | Where-Object Name -eq 'squad.prompt.md')[0].Meta['argument-hint'] | Should -Match ([regex]::Escape('[delivery=background]'))
    }
}

Describe 'Background Workstreams Procedure (RTE-51, RTE-52)' {
    It 'is opt-in, interactive-only, never overrides disjointness, and keeps the Scribe the only writer' {
        $script:BgText | Should -Match ([regex]::Escape('never autonomous, autopilot, or Watch) when the user passes `delivery=background`'))
        $script:BgText | Should -Match ([regex]::Escape('`delivery=background` still requires disjoint write sets and never overrides them'))
        $script:BgText | Should -Match ([regex]::Escape('the Squad Scribe stays the only writer'))
        $script:Parallelism | Should -Match ([regex]::Escape('carries one `historyRecords` entry per stage'))
    }

    It 'runs coordinator-only gates in the foreground and backgrounds only bounded or planned workstreams' {
        $script:BgText | Should -Match ([regex]::Escape('Run every coordinator-only gate in the foreground before any launch: discovery, intake, council, Cost Preflight, the Risk Gate, and routing tiers'))
        $script:BgText | Should -Match ([regex]::Escape('qualifies for the *Bounded Lane*, or when it already has a confirmed plan artifact on disk'))
        $script:BgText | Should -Match ([regex]::Escape('presents the plan in a second approval before any implementation'))
        $script:BgText | Should -Match ([regex]::Escape('covers bounded and planned workstreams only'))
        $script:BgText | Should -Match ([regex]::Escape('An `escalate`-tier owner, or a Risk Gate or Impactful-Action Gate trigger, keeps that workstream in the foreground'))
    }

    It 'requires every owner and an independent named reviewer in the lead''s agents list, else the foreground' {
        $script:BgText | Should -Match ([regex]::Escape('Every owner and the reviewer of a lead workstream must be in the lead''s `agents:` list'))
        $script:BgText | Should -Match ([regex]::Escape('it must differ from every owner agent'))
        $script:BgText | Should -Match ([regex]::Escape('run that workstream in the foreground'))
    }

    It 'takes one approval and launches in background in one block under the concurrency cap' {
        $script:BgText | Should -Match ([regex]::Escape('Present ONE confirmation listing every workstream'))
        $script:BgText | Should -Match ([regex]::Escape('each owner''s routing tier, write set, `Model` cell (or `none`)'))
        $script:BgText | Should -Match ([regex]::Escape('`mode: "background"`, all in ONE tool-call block'))
        $script:BgText | Should -Match ([regex]::Escape('The cap is `COPILOT_SUBAGENT_MAX_CONCURRENT`'))
        $script:BgText | Should -Match ([regex]::Escape('else 4'))
        $script:BgText | Should -Match ([regex]::Escape('counts only the subagents you launch that run at once'))
        $script:BgText | Should -Match ([regex]::Escape('an impactful action still stops'))
        $script:BgText | Should -Match ([regex]::Escape('run the workstreams sequentially and say so'))
        @(Find-InlineWorkPermission -Text $script:BgText) | Should -BeNullOrEmpty
    }

    It 'dispatches a bounded workstream directly on each Model cell and uses a lead only for multi-stage work' {
        $script:BgText | Should -Match ([regex]::Escape('A bounded workstream needs no lead: the coordinator dispatches its owner and reviewer directly'))
        $script:BgText | Should -Match ([regex]::Escape('Use a `Squad Workstream Lead` only for a multi-stage workstream'))
        $script:BgText | Should -Match ([regex]::Escape('the owner''s `Model` cell as `model` exactly as written when the routing mode writes one (otherwise no `model`)'))
        $script:BgText | Should -Match ([regex]::Escape('a review-class dispatch on its own `Model` cell or pin, as in the foreground'))
        $script:BgText | Should -Match ([regex]::Escape('it copies each `Model` cell and picks no model'))
        $script:BgText | Should -Match ([regex]::Escape('an owner at depth 1 keeps its own tools and nests nothing'))
    }

    It 'names no model id and no bounded pick' {
        $script:BgText | Should -Not -Match '(?i)bounded pick|boundedPick|(?<![a-z])-Bounded\b'
        $script:BgText | Should -Not -Match '(?i)\b(claude|gpt-|gemini|grok)'
    }

    It 'collects in one read_agent block and verifies artifacts on disk before reporting' {
        $script:BgText | Should -Match ([regex]::Escape('Wait on every running background agent in ONE tool-call block of `read_agent` calls with `wait: true`'))
        $script:BgText | Should -Match ([regex]::Escape('read that lead with `read_agent`, then VERIFY before reporting'))
        $script:BgText | Should -Match ([regex]::Escape('read the verdict from that artifact on disk, never from the reviewer''s or the lead''s message'))
        $script:BgText | Should -Match ([regex]::Escape('reported as not delivered, never as done'))
        $script:BgText | Should -Match ([regex]::Escape('A lead that errors, returns blocked, or reports nothing leaves its workstream not delivered'))
        $script:BgText | Should -Match ([regex]::Escape('becomes a new workstream under these rules, with its own approval, or waits when its write set overlaps a running workstream'))
    }

    It 'hands each payload to the Scribe, which runs the script, one hand-off at a time per squad root' {
        $script:BgText | Should -Match ([regex]::Escape('Hand each workstream''s payload to the Squad Scribe, which runs `scripts/Write-SquadHandoff.ps1` as its first action (*Script Hand-off*), one hand-off at a time per squad root'))
        $script:BgText | Should -Match ([regex]::Escape('The coordinator and the lead never run `Write-SquadHandoff.ps1`.'))
        $script:BgText | Should -Match ([regex]::Escape('advances `state.json` `turn` by one'))
        $script:BgText | Should -Match ([regex]::Escape('never the lead''s completion time'))
        $script:BgText | Should -Match ([regex]::Escape('`orchestration.leadConsumption`'))
        $script:BgText | Should -Match ([regex]::Escape('and the ledger sums it once'))
        $script:BgText | Should -Match ([regex]::Escape('records the same `workstream` and `launchedAt` as a `* Workstream:` line'))
        $script:BgText | Should -Not -Match '(?i)\b(coordinator|you)\s+(runs?|writes?)\s+(each|the)\s+(workstream''s\s+)?(ordinary\s+)?hand-off'
    }
}

Describe 'Payload and contract carry the workstream fields (RTE-52)' {
    It 'the Scribe payload template and Script Hand-off carry workstream, launchedAt, and leadConsumption' {
        $template = Get-SquadReferenceBody -Name 'scribe-payload-template.md'
        $template | Should -Match ([regex]::Escape('`workstream`?, `launchedAt`?'))
        $template | Should -Match ([regex]::Escape('`leadConsumption`?'))
        $template | Should -Match ([regex]::Escape('workstream: <id; Scribe writes * Workstream: line | omit>'))
        $template | Should -Match ([regex]::Escape('launchedAt: <ISO, with workstream>'))
        (Get-SquadReferenceBody -Name 'operating-procedure.md') | Should -Match ([regex]::Escape('"leadConsumption"? (workstream only)'))
        (Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'scripts/Write-SquadHandoff.ps1') -Raw) | Should -Match ([regex]::Escape("'leadConsumption'"))
    }

    It 'the behavior contract carries RTE-51 and RTE-52' {
        $contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../squad-behavior-contract.md') -Raw
        $contract | Should -Match '(?m)^\| RTE-51 \| \*\*Background workstreams fan out under one approval'
        $contract | Should -Match '(?m)^\| RTE-52 \| \*\*Concurrent workstreams are recorded by the Scribe one at a time'
    }
}
