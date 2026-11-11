#requires -Version 7.0
[CmdletBinding()]
param(
    [string[]]$Target,
    [string[]]$Skill,
    [switch]$List,
    [switch]$Copy,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repo      = $PSScriptRoot
$claudeDir = Join-Path $HOME '.claude/skills'
$agentsDir = Join-Path $HOME '.agents/skills'

# Skills live in skills/<name> or skills/<group>/<name> and are installed flat.
function Get-SkillMap {
    $root = Join-Path $repo 'skills'
    if (-not (Test-Path $root)) { return @() }
    @(Get-ChildItem $root -Recurse -Depth 2 -Filter SKILL.md -File |
        Sort-Object FullName |
        ForEach-Object { [pscustomobject]@{ Name = $_.Directory.Name; Path = $_.Directory.FullName } })
}

function Resolve-Target([string]$Name) {
    switch ($Name) {
        'claude'  { $claudeDir }
        'agents'  { $agentsDir }
        'copilot' { $agentsDir }
        'both'    { $claudeDir; $agentsDir }
        default   { $Name }
    }
}

$skillMap = Get-SkillMap

if ($List) { $skillMap.Name; return }

$duplicates = @($skillMap | Group-Object Name | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) {
    throw "Duplicate skill names (they are installed flat, so they must be unique): $($duplicates.Name -join ', ')"
}

if (-not $Target) {
    if ([Console]::IsInputRedirected) {
        throw 'No -Target given and no interactive terminal available. Use -Target claude | agents | both | <path>.'
    }
    Write-Host 'Install skills for:'
    Write-Host '  1) Claude Code        (~/.claude/skills)'
    Write-Host '  2) Copilot / agents   (~/.agents/skills)'
    Write-Host '  3) Both'
    $Target = switch (Read-Host 'Choose [1-3]') {
        '1'     { 'claude' }
        '2'     { 'agents' }
        '3'     { 'both' }
        default { throw 'Invalid choice.' }
    }
}

$destinations = @($Target | ForEach-Object { Resolve-Target $_ } | Select-Object -Unique)

if ($destinations.Count -gt 1) {
    Write-Warning 'VS Code Copilot reads both ~/.claude/skills and ~/.agents/skills, so the same skill may show up twice there.'
}

if (-not $Skill) { $Skill = @($skillMap.Name) }
if ($Skill.Count -eq 0) { throw "No skills found under $repo/skills" }

$linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }

foreach ($dest in $destinations) {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    foreach ($name in $Skill) {
        $entry = $skillMap | Where-Object Name -eq $name | Select-Object -First 1
        $link  = Join-Path $dest $name

        if (-not $entry) {
            Write-Warning "skip:   $name (not found or missing SKILL.md)"
            continue
        }

        if (Test-Path $link) {
            $item = Get-Item $link -Force
            if ($item.LinkType) { Remove-Item $link -Force }
            elseif ($Force)     { Remove-Item $link -Recurse -Force }
            else {
                Write-Warning "skip:   $name (already exists at $link; use -Force to replace)"
                continue
            }
        }

        if ($Copy) {
            Copy-Item $entry.Path $link -Recurse
            Write-Host "copied: $name -> $link"
        } else {
            New-Item -ItemType $linkType -Path $link -Target $entry.Path | Out-Null
            Write-Host "linked: $name -> $link"
        }
    }
}