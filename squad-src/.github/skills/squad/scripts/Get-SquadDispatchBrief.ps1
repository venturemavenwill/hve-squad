#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Prints, in one read-only call, everything a coordinator otherwise discovers turn by
    turn before a bounded dispatch and its hand-off.
.DESCRIPTION
    Each coordinator turn resends its whole context, so every discovery turn (reading
    agent files, the rate table, the roster, the hand-off format) is paid again on every
    later turn. This script gathers those facts deterministically and prints one compact
    Markdown brief:

      - status: current UTC time, PowerShell version, initialization, federation, cost
        ceiling, ledger shape (ok, stub, partial), the next hand-off `turn`, and the
        concurrency cap (`COPILOT_SUBAGENT_MAX_CONCURRENT`, else 4);
      - roster: each role's agent, its frontmatter model pin, the rate-table row and tier
        that price it, its deliverable root, and its bounded pick from
        `Resolve-SquadModelRoute.ps1 -Bounded`;
      - consumption: a ready ten-field consumption object per role, sized by the
        dispatch-size estimator floors in `references/consumption-rates-template.md`;
      - hand-off: the resolved `Write-SquadHandoff.ps1` command line;
      - procedure: the verbatim Bounded Lane, Owner Finish Barrier, Script Hand-off and
        Hand-off Ledger Verification sections (plus Background Workstreams with
        -Background), so a bounded request needs no whole reference file.

    The script writes nothing. Exit codes: 0 brief printed; 1 usage error.
.PARAMETER SquadRoot
    The squad root (`.copilot-tracking/squad/`).
.PARAMETER RepoRoot
    The repository root that holds `.github/agents/`. Defaults to the current directory.
.PARAMETER SessionModel
    The coordinator's session model id, used for the orchestration consumption object.
.PARAMETER Background
    Also embed the Background Workstreams Procedure.
.EXAMPLE
    & .agents/skills/squad/scripts/Get-SquadDispatchBrief.ps1 -SquadRoot .copilot-tracking/squad -SessionModel claude-sonnet-5
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [string]$RepoRoot = (Get-Location).Path,

    [string]$SessionModel,

    [switch]$Background
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$refs = Join-Path $skillRoot 'references'
if (-not (Test-Path -LiteralPath $SquadRoot -PathType Container)) {
    Write-Error "Get-SquadDispatchBrief: squad root not found: $SquadRoot"
    exit 1
}
$SquadRoot = (Resolve-Path -LiteralPath $SquadRoot).Path

function Get-Section {
    param([string]$File, [string]$Heading)
    $lines = @(Get-Content -LiteralPath (Join-Path $refs $File) -Encoding utf8)
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].StartsWith($Heading)) { $start = $i; break } }
    if ($start -lt 0) { return "(section '$Heading' not found in $File; read the file)" }
    $level = ($Heading -split ' ')[0].Length
    $end = $start + 1
    while ($end -lt $lines.Count -and $lines[$end] -notmatch "^#{1,$level} ") { $end++ }
    ($lines[$start..($end - 1)] -join "`n").TrimEnd()
}

function Get-TableRows {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @(Get-Content -LiteralPath $Path -Encoding utf8 | Where-Object { $_ -match '^\|' -and $_ -notmatch '^\|\s*-' } |
        ForEach-Object { , @($_.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim().Trim('`').Trim() }) })
}

$out = [System.Collections.Generic.List[string]]::new()
$utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$out.Add('# Squad Dispatch Brief')
$out.Add('')
$out.Add("utc: $utc | pwsh: $($PSVersionTable.PSVersion) | squadRoot: $SquadRoot | skill: $skillRoot")

$teamPath = Join-Path $SquadRoot 'team.md'
$statePath = Join-Path $SquadRoot 'state.json'
if (-not (Test-Path -LiteralPath $teamPath) -or -not (Test-Path -LiteralPath $statePath)) {
    $out.Add('status: NOT INITIALIZED. This brief does not cover Init: read the three reference files whole.')
    $out -join "`n"
    exit 0
}

$stateText = Get-Content -LiteralPath $statePath -Raw -Encoding utf8
$state = $stateText | ConvertFrom-Json -AsHashtable
$turn = [int]$state['turn']
# ConvertFrom-Json turns ISO strings into local DateTime values; print the stored text.
$updated = if ($stateText -match '"updated"\s*:\s*"([^"]*)"') { $Matches[1] } else { '' }
$federated = (Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md')) -or ($SquadRoot -match '[\\/]members[\\/][^\\/]+[\\/]?$')
$preflight = if ($state['currentRun'] -is [hashtable]) { $state['currentRun']['costPreflight'] } else { $null }
$ceiling = $null -ne $preflight -and ($null -ne $preflight['ceilingUsd'] -or ($preflight['decision'] -and $preflight['decision'] -ne 'not-requested'))

$ledgerPath = Join-Path $SquadRoot 'consumption.md'
$ledgerText = if (Test-Path -LiteralPath $ledgerPath) { Get-Content -LiteralPath $ledgerPath -Raw -Encoding utf8 } else { '' }
$sections = @('## Attribution', '## Usage & Cost', '### Derivation' | Where-Object { $ledgerText -match "(?m)^$([regex]::Escape($_))\s*$" })
$ledger = switch ($sections.Count) { 3 { 'ok' } 0 { 'stub (do not dispatch the Scribe; the next script hand-off reseeds it)' } default { 'partial (reconcile through the Squad Scribe first)' } }

$capText = $env:COPILOT_SUBAGENT_MAX_CONCURRENT
$cap = if ($capText -match '^\d+$' -and [int]$capText -gt 0) { [int]$capText } else { 4 }

$covered = -not $federated -and -not $ceiling
$out.Add("state: schema $($state['schemaVersion']), turn $turn (next hand-off turn: $($turn + 1)), mode $($state['mode']), updated $updated")
$out.Add("federation: $(if ($federated) { 'yes' } else { 'no' }) | cost ceiling: $(if ($ceiling) { 'active' } else { 'none' }) | ledger: $ledger | concurrency cap: $cap")
if ($covered) {
    $out.Add('coverage: for a request that meets every Bounded Lane criterion below, this brief replaces reading 00-index.md, operating-procedure.md, gates-and-modes.md, agent files, and the rate table. Any other request: read the three reference files whole.')
}
else {
    $out.Add('coverage: NONE (federation or active cost ceiling). Read the three reference files whole; use the roster below only as data.')
}

# Agent pins and dispatchability from frontmatter.
$pins = @{}
$blocked = @{}
$agentDir = Join-Path $RepoRoot '.github/agents'
if (Test-Path -LiteralPath $agentDir) {
    foreach ($file in Get-ChildItem -LiteralPath $agentDir -Recurse -Filter '*.agent.md' -File) {
        $head = (Get-Content -LiteralPath $file.FullName -TotalCount 40 -Encoding utf8) -join "`n"
        if ($head -notmatch '(?s)^---\n(.*?)\n---') { continue }
        $front = $Matches[1]
        if ($front -notmatch '(?m)^name:\s*["'']?(.+?)["'']?\s*$') { continue }
        $name = $Matches[1]
        $model = if ($front -match '(?m)^model:\s*["'']?(.+?)["'']?\s*$') { $Matches[1] -replace '\s*\(copilot\)\s*$', '' } else { '' }
        $pins[$name] = $model
        $blocked[$name] = $front -match '(?m)^disable-model-invocation:\s*true\s*$'
    }
}

# Rate rows: the squad root's table, else the skill template.
$rates = @(Get-TableRows (Join-Path $SquadRoot 'consumption-rates.md') | Where-Object { $_.Count -ge 3 -and $_[0] -ne 'Model (as routed)' })
if ($rates.Count -eq 0) { $rates = @(Get-TableRows (Join-Path $refs 'consumption-rates-template.md') | Where-Object { $_.Count -ge 3 -and $_[0] -ne 'Model (as routed)' }) }
function Find-Rate {
    param([string]$Model)
    if (-not $Model) { return $null }
    $key = $Model.ToLowerInvariant()
    foreach ($row in $rates) { if ($row[0].ToLowerInvariant() -eq $key -or $row[1].ToLowerInvariant() -eq $key) { return $row } }
    $null
}

# Bounded picks; the helper runs as a child process because it may call exit.
$routes = @{}
$routeNote = ''
$helper = Join-Path $PSScriptRoot 'Resolve-SquadModelRoute.ps1'
try {
    $json = & pwsh -NoProfile -File $helper -SquadRoot $SquadRoot -Bounded 2>$null | Out-String
    foreach ($role in ($json | ConvertFrom-Json).roles) { $routes[$role.role] = $role }
}
catch { $routeNote = 'bounded picks unavailable: run Resolve-SquadModelRoute.ps1 -Bounded' }

$estimator = @{
    research       = @(12, 40000, 4000, 1250)
    planning       = @(15, 60000, 4000, 2000)
    implementation = @(35, 60000, 6000, 2000)
    review         = @(18, 50000, 4000, 1500)
    bookkeeping    = @(4, 15000, 3000, 800)
}
function New-Consumption {
    param([string]$Model, [string]$Source, [string]$Class)
    $floor = if ($estimator.ContainsKey($Class)) { $estimator[$Class] } else { $estimator['implementation'] }
    $t, $base, $growth, $perTurn = $floor
    $gross = $t * ($base + $growth * ($t - 1) / 2)
    $rate = Find-Rate $Model
    [ordered]@{
        model              = $Model
        model_source       = $Source
        priced_as          = if ($rate) { $rate[0] } else { '' }
        model_tier         = if ($rate) { $rate[2] } else { 'default' }
        internal_turns     = $t
        input_tokens       = [long][math]::Round($gross * 0.2)
        cached_tokens      = [long][math]::Round($gross * 0.8)
        cache_write_tokens = if ($Model -match 'claude') { [long]($base + $growth * ($t - 1)) } else { 0 }
        output_tokens      = [long]($t * $perTurn)
        basis              = 'estimated'
    }
}

$out.Add('')
$out.Add('## Roster')
$out.Add('')
$out.Add('Dispatch each role with `task` `agent_type` (and `name`) set to its Agent cell verbatim; never `general-purpose`, `task`, or another built-in type.')
$out.Add('')
$out.Add('| Role | Agent | Dispatchable | Pin | Priced as (tier) | Deliverable root | Bounded pick |')
$out.Add('| ---- | ----- | ------------ | --- | ---------------- | ---------------- | ------------ |')
$consumption = [System.Collections.Generic.List[string]]::new()
$unreachable = [System.Collections.Generic.List[string]]::new()
foreach ($row in Get-TableRows $teamPath) {
    if ($row.Count -lt 6 -or $row[0] -eq 'Role') { continue }
    $role = $row[0]; $agent = $row[1]; $root = $row[4]
    $pin = if ($pins.ContainsKey($agent)) { $pins[$agent] } else { $null }
    $pinText = if ($null -eq $pin) { 'agent file not found' } elseif ($pin) { $pin } else { 'none (session-inherited)' }
    $rate = Find-Rate $pin
    $priced = if ($rate) { "$($rate[0]) ($($rate[2]))" } elseif ($pin) { 'no rate row' } else { 'session model' }
    $route = $routes[$role]
    $pick = if ($route -and $route.PSObject.Properties['boundedPick'] -and $route.boundedPick) { [string]$route.boundedPick } else { '—' }
    $alts = if ($row[2] -and $row[2] -ne '—') { " (alternates: $($row[2]); cue: $($row[3]))" } else { '' }
    $reach = if ($null -eq $pin) { 'no (not installed)' } elseif ($blocked[$agent]) { 'no (disable-model-invocation)' } else { 'yes' }
    if ($reach -ne 'yes') { $unreachable.Add("$role -> $agent") }
    $out.Add("| $role | $agent$alts | $reach | $pinText | $priced | $root | $pick |")
    $class = if ($route -and $route.PSObject.Properties['class']) { [string]$route.class } else { 'implementation' }
    if ($pick -ne '—') {
        $c = New-Consumption -Model $pick -Source 'cli-pinned' -Class $class
        $consumption.Add("- $role on bounded pick (add ``""passedModel"": ""$pick""``): $($c | ConvertTo-Json -Compress)")
    }
    elseif ($pin -and $class -eq 'review') {
        $c = New-Consumption -Model $pin -Source 'agent-pinned' -Class $class
        $consumption.Add("- $role on its pin: $($c | ConvertTo-Json -Compress)")
    }
}
$out.Add('')
$out.Add($(if ($unreachable.Count -eq 0) { 'roster precheck (Step 1b): PASS, every Primary is installed and dispatchable; no agent-file read is needed.' } else { "roster precheck (Step 1b): FAIL for $($unreachable -join ', '); escalate before dispatching those roles." }))
if ($routeNote) { $out.Add(''); $out.Add($routeNote) }

$out.Add('')
$out.Add('## Consumption objects (estimator floors; raise internal_turns when the dispatch reported more)')
$out.Add('')
$consumption | ForEach-Object { $out.Add($_) }
if ($SessionModel) {
    $sessionRate = Find-Rate $SessionModel
    $c = New-Consumption -Model $(if ($sessionRate) { $sessionRate[0] } else { $SessionModel }) -Source 'session-inherited' -Class 'planning'
    $out.Add("- orchestration (set internal_turns to your own turn count): $($c | ConvertTo-Json -Compress)")
}

$out.Add('')
$out.Add('## Hand-off')
$out.Add('')
$out.Add("Payload ``turn`` = $($turn + 1); ``timestamp`` = the current UTC time when you write it (this brief's utc is $utc). Run:")
$out.Add("``& '$(Join-Path $PSScriptRoot 'Write-SquadHandoff.ps1')' -SquadRoot '$SquadRoot' -PayloadJson " + '$p` with `$p` a single-quoted here-string.')

$out.Add('')
$out.Add('## Procedure (verbatim)')
$out.Add('')
$out.Add((Get-Section 'gates-and-modes.md' '### Bounded Lane'))
$out.Add('')
$out.Add((Get-Section 'operating-procedure.md' '### Owner Finish Barrier'))
$out.Add('')
$out.Add((Get-Section 'operating-procedure.md' '### Script Hand-off'))
if ($Background) {
    $out.Add('')
    $out.Add((Get-Section 'gates-and-modes.md' '## Background Workstreams Procedure'))
}

$text = $out -join "`n"
# The CLI spills shell output over 20,480 bytes to a temp file, costing extra read turns.
$limit = 20480
if ($env:COPILOT_LARGE_OUTPUT_THRESHOLD_BYTES -match '^\d+$') { $limit = [int]$env:COPILOT_LARGE_OUTPUT_THRESHOLD_BYTES }
if ([Text.Encoding]::UTF8.GetByteCount($text) -gt $limit) {
    [Console]::Error.WriteLine("WARN brief exceeds the $limit-byte inline output limit; the host will save it to a file")
}
$text
exit 0
