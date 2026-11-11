#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkItem,
    [string]$Org,
    [string]$Project,
    [string]$Root = '.'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'collector-lib.ps1')
$target = Resolve-TaskTarget -WorkItem $WorkItem -Org $Org -Project $Project
Invoke-TaskCollection -Target $target -Root $Root | ConvertTo-Json -Depth 10