#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('claude', 'agents')][string]$Target = 'claude',
    [string]$Path,
    [string[]]$Skill,
    [switch]$Copy,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

$dest = if ($Path) { $Path }
        elseif ($Target -eq 'agents') { Join-Path $HOME '.agents/skills' }
        else { Join-Path $HOME '.claude/skills' }

New-Item -ItemType Directory -Force -Path $dest | Out-Null

if (-not $Skill) {
    $Skill = Get-ChildItem (Join-Path $repo 'skills') -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
        ForEach-Object Name
}

$linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }

foreach ($name in $Skill) {
    $src  = Join-Path $repo "skills/$name"
    $link = Join-Path $dest $name

    if (-not (Test-Path (Join-Path $src 'SKILL.md'))) {
        Write-Warning "skip: $name (no existe o no tiene SKILL.md)"
        continue
    }

    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.LinkType) { Remove-Item $link -Force }
        elseif ($Force)     { Remove-Item $link -Recurse -Force }
        else { Write-Warning "skip: $name (ya existe; usa -Force)"; continue }
    }

    if ($Copy) {
        Copy-Item $src $link -Recurse
        Write-Host "copiada:  $name -> $link"
    } else {
        New-Item -ItemType $linkType -Path $link -Target $src | Out-Null
        Write-Host "enlazada: $name -> $link"
    }
}