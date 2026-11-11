#requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'collector-lib.ps1')

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -cne $Expected) { throw "FAIL: $Label. Expected '$Expected', got '$Actual'." }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    if (-not $threw) { throw "FAIL: $Label did not throw." }
}

$target = Resolve-TaskTarget -WorkItem '42' -Org 'example' -Project 'Project One'
Assert-Equal $target.BaseUrl 'https://dev.azure.com/example/Project%20One' 'Encoded project'
$urlTarget = Resolve-TaskTarget -WorkItem 'https://dev.azure.com/example/Project%20One/_workitems/edit/42'
Assert-Equal $urlTarget.Id '42' 'Modern URL ID'
$legacy = Resolve-TaskTarget -WorkItem 'https://example.visualstudio.com/Project%20One/_workitems/edit/42'
Assert-Equal $legacy.Project 'Project One' 'Legacy URL project'
Assert-Throws { Resolve-TaskTarget -WorkItem '../42' -Org 'example' -Project 'project' } 'Invalid ID'
Assert-Throws { Resolve-TaskTarget -WorkItem 'https://evil.test/project/_workitems/edit/42' } 'External host'
Assert-Throws { Resolve-TaskTarget -WorkItem '42' } 'Missing configuration'
Assert-Equal (Test-TaskUri -Uri 'https://dev.azure.com/other/_apis/wit/workitems/42' -Org 'example') $false 'Cross-org URL'
Assert-Equal (Test-TaskUri -Uri 'https://example.visualstudio.com.evil.test/file' -Org 'example') $false 'Host suffix attack'
Assert-Equal (Test-TaskUri -Uri 'https://user@example.visualstudio.com/file' -Org 'example') $false 'Userinfo URL'
Write-Output 'PASS: target resolution and URL boundaries'

$script:fixture = @{
    id = 42; rev = 1
    fields = @{
        'System.Title' = 'Synthetic task'
        'System.Description' = '<p>Keep original &amp; text.</p><img src="https://external.test/image.png">'
        'Microsoft.VSTS.Common.AcceptanceCriteria' = "No defaults. `````` not a fence escape."
        'Custom.TechnicalDesign' = 'Original custom field'
    }
    relations = @(@{ rel = 'AttachedFile'; url = 'https://dev.azure.com/example/_apis/wit/attachments/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; attributes = @{ name = '../../requirements.pdf' } })
}
$script:failMain = $false
$script:failComments = $false
$script:requested = [System.Collections.Generic.List[string]]::new()
function Invoke-TaskRequest {
    param([Uri]$Uri, [string]$Org, [long]$MaxBytes = 16MB, [switch]$Binary)
    $script:requested.Add($Uri.AbsoluteUri)
    if ($Uri.Host -ne 'dev.azure.com') { throw 'Test attempted an external request.' }
    if ($Binary) { return ,[Text.Encoding]::UTF8.GetBytes('synthetic PDF content') }
    if ($Uri.AbsolutePath -like '*/comments') {
        if ($script:failComments) { throw 'Synthetic comment failure' }
        if ($Uri.Query -match 'continuationToken=next') { return @{ comments = @(@{ id = 2; text = 'Second comment' }) } }
        return @{ comments = @(@{ id = 1; text = 'First comment' }); continuationToken = 'next' }
    }
    if ($script:failMain) { throw 'Synthetic main request failure' }
    return $script:fixture
}

$root = Join-Path ([IO.Path]::GetTempPath()) "ado-task-context-test-$([Guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($root) | Out-Null
try {
    $first = Invoke-TaskCollection -Target $target -Root $root
    Assert-Equal $first.Comments 2 'Comment pagination'
    Assert-Equal $first.Attachments 2 'All candidate types inventoried'
    Assert-Equal $first.CaptureStatus 'Partial capture' 'External image reported'
    $folder = Join-Path $root '.aw/tasks/42'
    $snapshot = Get-Content -LiteralPath (Join-Path $folder 'source.json') -Raw | ConvertFrom-Json -AsHashtable
    Assert-Equal $snapshot.WorkItem.fields.'Custom.TechnicalDesign' 'Original custom field' 'All fields retained'
    Assert-Equal $snapshot.Attachments[0].Status 'downloaded; not reviewed' 'Non-image attachment downloaded'
    Assert-Equal ($snapshot.Attachments[0].Path -match '\.\./') $false 'Safe attachment filename'
    Assert-Equal ($script:requested | Where-Object { $_ -like '*external.test*' }).Count 0 'No external HTTP call'
    $contextPath = Join-Path $folder 'context.md'
    $humanText = "# Human context`nDecision: keep this verbatim.`n## My plan`nDo not overwrite.`n"
    [IO.File]::WriteAllText($contextPath, $humanText)
    $second = Invoke-TaskCollection -Target $target -Root $root
    Assert-Equal $second.EvidenceChanged $false 'Stable evidence on repeat'
    Assert-Equal ([IO.File]::ReadAllText($contextPath)) $humanText 'Human notes and plan preserved'
    $script:fixture.rev = 2
    $script:fixture.fields.'System.Title' = 'Updated task'
    $changed = Invoke-TaskCollection -Target $target -Root $root
    Assert-Equal $changed.EvidenceChanged $true 'Changed source detected'
    Assert-Equal ([IO.File]::ReadAllText($contextPath)) $humanText 'Notes preserved on changed source'
    $before = [IO.File]::ReadAllText((Join-Path $folder 'source.json'))
    $script:failMain = $true
    Assert-Throws { Invoke-TaskCollection -Target $target -Root $root } 'Main request failure'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $folder 'source.json'))) $before 'Snapshot preserved on HTTP failure'
    $script:failMain = $false
    $script:failComments = $true
    $partial = Invoke-TaskCollection -Target $target -Root $root
    Assert-Equal $partial.CaptureStatus 'Partial capture' 'Comment failure visible'
    Assert-Throws { Invoke-TaskCollection -Target (Resolve-TaskTarget -WorkItem '42' -Org 'different' -Project 'Project One') -Root $root } 'Cross-org collision'
    Assert-Equal ([IO.File]::ReadAllText($contextPath)) $humanText 'Context untouched throughout'
    Write-Output 'PASS: capture, pagination, attachments, repeat, updates, failures and preservation'
}
finally { Remove-Item -LiteralPath $root -Recurse -Force }