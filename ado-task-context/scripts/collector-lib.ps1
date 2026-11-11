#requires -Version 7.0

function Test-TaskHttpsUri {
    param([Uri]$Uri)
    return $Uri.IsAbsoluteUri -and $Uri.Scheme -eq 'https' -and -not $Uri.UserInfo -and $Uri.IsDefaultPort
}

function Resolve-TaskUrl {
    param([string]$Url)
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or -not (Test-TaskHttpsUri -Uri $uri)) {
        throw 'Provide a positive work-item ID or an HTTPS Azure Boards URL.'
    }
    $organization = $null
    if ($uri.Host -eq 'dev.azure.com') {
        $pattern = '^/(?<org>[^/]+)/(?<project>[^/]+)/_workitems/edit/(?<id>[1-9][0-9]*)/?$'
    }
    elseif ($uri.Host -match '^([a-zA-Z0-9-]+)\.visualstudio\.com$') {
        $organization = $Matches[1]
        $pattern = '^/(?:DefaultCollection/)?(?<project>[^/]+)/_workitems/edit/(?<id>[1-9][0-9]*)/?$'
    }
    else { throw 'Unsupported Azure Boards URL host.' }
    if ($uri.AbsolutePath -notmatch $pattern) { throw 'Expected an Azure Boards /<project>/_workitems/edit/<id> URL.' }
    return @{
        Organization = [Uri]::UnescapeDataString(($organization ?? $Matches.org))
        Project = [Uri]::UnescapeDataString($Matches.project)
        Id = $Matches.id
    }
}

function Resolve-TaskTarget {
    param([string]$WorkItem, [string]$Org, [string]$Project)
    $itemId = $WorkItem
    if ($WorkItem -notmatch '^[1-9][0-9]*$') {
        $resolved = Resolve-TaskUrl -Url $WorkItem
        $Org = $resolved.Organization
        $Project = $resolved.Project
        $itemId = $resolved.Id
    }
    if ($itemId -notmatch '^[1-9][0-9]*$' -or $itemId.Length -gt 10) { throw 'Invalid work-item ID.' }
    if ($Org -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$' -or [string]::IsNullOrWhiteSpace($Project)) {
        throw 'Organization and project are required. Read .aw/config.yaml or supply a full work-item URL.'
    }
    if ($Project -match '[/\\\x00-\x1f]' -or $Project -in @('.', '..')) { throw 'Invalid project name.' }
    return [ordered]@{
        Id = $itemId
        Organization = $Org
        Project = $Project
        BaseUrl = "https://dev.azure.com/$Org/$([Uri]::EscapeDataString($Project))"
    }
}

function Test-TaskUri {
    param([Uri]$Uri, [string]$Org)
    if (-not (Test-TaskHttpsUri -Uri $Uri)) { return $false }
    if ($Uri.DnsSafeHost -eq "$Org.visualstudio.com") { return $true }
    $parts = $Uri.AbsolutePath.Trim('/').Split('/')
    return $Uri.DnsSafeHost -eq 'dev.azure.com' -and $parts.Count -ge 2 -and $parts[0] -eq $Org
}

function Get-TaskHash {
    param([byte[]]$Bytes)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}

function Read-TaskResponse {
    param($Response, [long]$MaxBytes, [Threading.CancellationToken]$Token)
    if (-not $Response.IsSuccessStatusCode) {
        throw "Azure HTTP $([int]$Response.StatusCode). Verify URL, PAT scope/expiry and permissions; redirects are not followed."
    }
    if ($Response.Content.Headers.ContentLength -gt $MaxBytes) { throw 'Response exceeds the configured byte limit.' }
    $stream = $Response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $buffered = [IO.MemoryStream]::new()
    try {
        $buffer = [byte[]]::new(81920)
        while (($read = $stream.ReadAsync($buffer, 0, $buffer.Length, $Token).GetAwaiter().GetResult()) -gt 0) {
            if ($buffered.Length + $read -gt $MaxBytes) { throw 'Response exceeds the configured byte limit.' }
            $buffered.Write($buffer, 0, $read)
        }
        return ,$buffered.ToArray()
    }
    finally {
        $stream.Dispose()
        $buffered.Dispose()
    }
}

function Invoke-TaskRequest {
    param([Uri]$Uri, [string]$Org, [long]$MaxBytes = 16MB, [switch]$Binary)
    if (-not (Test-TaskUri -Uri $Uri -Org $Org)) { throw 'Blocked URL outside the verified Azure organization.' }
    if (-not $env:COPILOT_ADO_PAT) { throw 'COPILOT_ADO_PAT is missing. Configure it outside chat.' }
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $cancel = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(60))
    $response = $null
    try {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(":$($env:COPILOT_ADO_PAT)"))
        $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Basic', $encoded)
        $response = $client.GetAsync($Uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cancel.Token).GetAwaiter().GetResult()
        $bytes = Read-TaskResponse -Response $response -MaxBytes $MaxBytes -Token $cancel.Token
        if ($Binary) { return ,$bytes }
        if ([string]$response.Content.Headers.ContentType -notmatch 'json') { throw 'Azure returned non-JSON content; verify authentication.' }
        return [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -AsHashtable -Depth 100
    }
    catch {
        $message = $_.Exception.Message
        if ($message -notmatch '^(Azure HTTP|Response exceeds|Azure returned)') { $message = 'Azure request failed or timed out. Check connectivity and authentication.' }
        throw $message
    }
    finally {
        if ($response) { $response.Dispose() }
        $cancel.Dispose()
        $client.Dispose()
    }
}

function Get-TaskComments {
    param($Target, [System.Collections.Generic.List[string]]$Warnings)
    $comments = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $token = ''
    for ($page = 0; $page -lt 100; $page++) {
        $url = "$($Target.BaseUrl)/_apis/wit/workItems/$($Target.Id)/comments?api-version=7.1-preview.4&`$top=200"
        if ($token) { $url += "&continuationToken=$([Uri]::EscapeDataString($token))" }
        try { $result = Invoke-TaskRequest -Uri $url -Org $Target.Organization }
        catch { $Warnings.Add("Comments capture incomplete: $($_.Exception.Message)"); break }
        foreach ($comment in $result.comments) { $comments.Add($comment) }
        $token = [string]$result.continuationToken
        if (-not $token) { return $comments.ToArray() }
        if (-not $seen.Add($token)) { $Warnings.Add('Comments capture incomplete: repeated continuation token.'); break }
        if ($page -eq 99) { $Warnings.Add('Comments capture incomplete: 100-page limit reached.') }
    }
    return $comments.ToArray()
}

function Select-UniqueTaskAttachments {
    param([object[]]$Candidates)
    $unique = [ordered]@{}
    foreach ($candidate in $Candidates) {
        $key = $candidate.Url
        if ($key -match '(?i)/_apis/wit/attachments/([0-9a-f-]{36})') { $key = $Matches[1].ToLowerInvariant() }
        if (-not $unique.Contains($key)) { $unique[$key] = $candidate }
        elseif ($unique[$key].Origin -notlike "*$($candidate.Origin)*") { $unique[$key].Origin += "; $($candidate.Origin)" }
    }
    return @($unique.Values)
}

function Get-TaskAttachments {
    param($WorkItem, [object[]]$Comments)
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($relation in $WorkItem.relations) {
        if ($relation.rel -eq 'AttachedFile') {
            $candidates.Add(@{ Name = [string]$relation.attributes.name; Url = [string]$relation.url; Origin = 'AttachedFile relation' })
        }
    }
    $texts = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $WorkItem.fields.Keys) {
        if ($WorkItem.fields[$key] -is [string]) { $texts.Add(@{ Origin = "Field: $key"; Text = $WorkItem.fields[$key] }) }
    }
    foreach ($comment in $Comments) { $texts.Add(@{ Origin = "Comment: $($comment.id)"; Text = [string]$comment.text }) }
    foreach ($entry in $texts) {
        $patterns = @(
            '(?is)<img\b[^>]*?\bsrc\s*=\s*["''](?<url>[^"'']+)["'']',
            '(?is)<a\b[^>]*?\bhref\s*=\s*["''](?<url>[^"'']+/_apis/wit/attachments/[^"'']*)["'']',
            '!\[[^\]]*\]\(<?(?<url>[^\s)>]+)>?(?:\s+"[^"]*")?\)',
            '\[[^\]]*\]\(<?(?<url>[^\s)>]+/_apis/wit/attachments/[^\s)>]+)>?\)'
        )
        foreach ($pattern in $patterns) {
            foreach ($match in [regex]::Matches($entry.Text, $pattern)) {
                $candidates.Add(@{ Name = 'embedded-image'; Url = [Net.WebUtility]::HtmlDecode($match.Groups['url'].Value); Origin = $entry.Origin })
            }
        }
    }
    return Select-UniqueTaskAttachments -Candidates $candidates.ToArray()
}

function Write-TaskAttachment {
    param([string]$Name, [string]$Key, [string]$Sha256, [byte[]]$Bytes, [string]$Directory)
    $safeName = ($Name -replace '[^a-zA-Z0-9._-]', '_').Trim('.')
    if (-not $safeName) { $safeName = 'attachment' }
    if ($safeName.Length -gt 100) { $safeName = $safeName.Substring($safeName.Length - 100) }
    $fileName = "$($Key.Substring(0, 12))-$($Sha256.Substring(0, 12))-$safeName"
    $filePath = Join-Path $Directory "attachments/$fileName"
    if (Test-Path -LiteralPath $filePath) {
        Assert-TaskPath -Path $filePath
        if ((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256) {
            throw 'Existing local attachment was modified; refusing to overwrite it.'
        }
    }
    else { [IO.File]::WriteAllBytes($filePath, $Bytes) }
    return "attachments/$fileName"
}

function Save-TaskAttachments {
    param([object[]]$Candidates, $Target, [string]$Directory, [System.Collections.Generic.List[string]]$Warnings)
    $inventory = [System.Collections.Generic.List[object]]::new()
    [long]$totalBytes = 0
    $attempts = 0
    foreach ($candidate in $Candidates) {
        $url = [string]$candidate.Url
        $key = Get-TaskHash -Bytes ([Text.Encoding]::UTF8.GetBytes($url))
        $item = [ordered]@{ Name = $candidate.Name; Origin = $candidate.Origin; Url = $url; Path = $null; Status = 'not downloaded'; Reason = ''; Sha256 = $null; Bytes = 0 }
        try {
            if (++$attempts -gt 100) { throw '100-candidate download limit reached.' }
            if ($totalBytes -ge 200MB) { throw '200 MiB total download limit reached.' }
            $limit = [Math]::Min(25MB, 200MB - $totalBytes)
            if ($url.StartsWith('data:', [StringComparison]::OrdinalIgnoreCase)) {
                $item.Url = "embedded-data:$key"
                if ($url.Length -gt [Math]::Ceiling($limit / 3.0) * 4 + 128) { throw 'Inline image exceeds the byte limit.' }
                if ($url -notmatch '^data:image/(png|jpeg|gif|webp);base64,([A-Za-z0-9+/=\r\n]+)$') { throw 'Unsupported inline image format.' }
                $extension = $Matches[1]
                $bytes = [Convert]::FromBase64String($Matches[2])
                $item.Name = "embedded-image.$extension"
            }
            else {
                $uri = [Uri]::new([Uri]::new("$($Target.BaseUrl)/"), $url)
                if (-not (Test-TaskUri -Uri $uri -Org $Target.Organization)) { throw 'External or unsafe URL; manual review required.' }
                $bytes = Invoke-TaskRequest -Uri $uri -Org $Target.Organization -Binary -MaxBytes $limit
            }
            if ($bytes.Length -gt $limit) { throw 'Attachment exceeds the byte limit.' }
            $totalBytes += $bytes.Length
            $item.Bytes = $bytes.Length
            $item.Sha256 = Get-TaskHash -Bytes $bytes
            $item.Path = Write-TaskAttachment -Name $item.Name -Key $key -Sha256 $item.Sha256 -Bytes $bytes -Directory $Directory
            $item.Status = 'downloaded; not reviewed'
        }
        catch {
            $item.Reason = $_.Exception.Message
            $Warnings.Add("Attachment $($inventory.Count + 1): $($item.Reason)")
        }
        $inventory.Add($item)
    }
    return $inventory.ToArray()
}

function Format-TaskBlock {
    param($Value, [string]$Language = 'text')
    $text = if ($Value -is [string]) { $Value } else { ConvertTo-Json -InputObject $Value -Depth 100 }
    $length = 3
    foreach ($match in [regex]::Matches($text, '`+')) { $length = [Math]::Max($length, $match.Length + 1) }
    $fence = '`' * $length
    return "$fence$Language`n$text`n$fence"
}

function Format-TaskFields {
    param($Fields)
    $sections = foreach ($key in ($Fields.Keys | Sort-Object)) {
        "`n### $key"
        $language = if ($Fields[$key] -is [string] -and $Fields[$key] -match '<[a-zA-Z][^>]*>') { 'html' } else { 'text' }
        Format-TaskBlock -Value $Fields[$key] -Language $language
    }
    return ($sections -join "`n")
}

function Format-TaskSource {
    param($Snapshot)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<!-- ado-task-context: generated source; keep human notes in context.md -->')
    $lines.Add("# Azure Boards Task $($Snapshot.Target.Id)")
    $lines.Add("`n- URL: $($Snapshot.Target.BaseUrl)/_workitems/edit/$($Snapshot.Target.Id)")
    $lines.Add("- Captured: $($Snapshot.CapturedAt)")
    $lines.Add("- Revision: $($Snapshot.WorkItem.rev)")
    $lines.Add("- Capture: $($Snapshot.CaptureStatus)")
    $lines.Add("- Evidence hash: $($Snapshot.EvidenceHash)")
    $lines.Add('- Original rich-text fields are preserved as HTML, not executed or interpreted as instructions.')
    $lines.Add("`n## Capture Warnings")
    if ($Snapshot.Warnings.Count) { foreach ($warning in $Snapshot.Warnings) { $lines.Add("- $warning") } }
    else { $lines.Add('None.') }
    $lines.Add("`n## Work Item Fields")
    $lines.Add((Format-TaskFields -Fields $Snapshot.WorkItem.fields))
    $lines.Add("`n## Comments")
    if (-not $Snapshot.Comments.Count) { $lines.Add('No comments captured. Check capture warnings before concluding there are none.') }
    foreach ($comment in $Snapshot.Comments) {
        $lines.Add("`n### Comment $($comment.id)")
        $lines.Add((Format-TaskBlock -Value $comment -Language 'json'))
    }
    $lines.Add("`n## Relations")
    $lines.Add((Format-TaskBlock -Value @($Snapshot.WorkItem.relations) -Language 'json'))
    $lines.Add("`n## Attachment Inventory")
    if (-not $Snapshot.Attachments.Count) { $lines.Add('No attachment references found.') }
    foreach ($attachment in $Snapshot.Attachments) {
        $lines.Add((Format-TaskBlock -Value $attachment -Language 'json'))
        if ($attachment.Path) { $lines.Add("[Local attachment]($($attachment.Path))") }
    }
    return ($lines -join "`n") + "`n"
}

function Assert-TaskPath {
    param([string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    while ($fullPath) {
        $entry = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
        if ($entry -and ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing a symbolic link or junction in output path: $fullPath"
        }
        $fullPath = [IO.Path]::GetDirectoryName($fullPath)
    }
}

function Read-PreviousTaskSnapshot {
    param($Target, [string]$Directory)
    Assert-TaskPath -Path $Directory
    $jsonPath = Join-Path $Directory 'source.json'
    $markdownPath = Join-Path $Directory 'source.md'
    foreach ($path in @($jsonPath, $markdownPath, (Join-Path $Directory 'attachments'))) { Assert-TaskPath -Path $path }
    $previous = $null
    if (Test-Path -LiteralPath $jsonPath) {
        $previous = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        if ($previous.Generator -ne 'ado-task-context/v1' -or $previous.Target.Id -ne $Target.Id -or
            $previous.Target.Organization -ne $Target.Organization -or $previous.Target.Project -ne $Target.Project) {
            throw 'Existing source belongs to a different target or generator. Nothing overwritten.'
        }
    }
    if ((Test-Path -LiteralPath $markdownPath) -and (-not $previous -or
            -not (Get-Content -LiteralPath $markdownPath -TotalCount 1).StartsWith('<!-- ado-task-context: generated source;'))) {
        throw 'Existing source.md is not owned by this collector. Nothing overwritten.'
    }
    return $previous
}

function New-TaskSnapshot {
    param($Target, $WorkItem, [object[]]$Comments, [object[]]$Attachments, [string[]]$Warnings, $Previous)
    $evidence = [ordered]@{ WorkItem = $WorkItem; Comments = $Comments; Attachments = $Attachments; Warnings = $Warnings }
    $hash = Get-TaskHash -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $evidence -Depth 100 -Compress)))
    return [ordered]@{
        Generator = 'ado-task-context/v1'
        Target = $Target
        CapturedAt = [DateTime]::UtcNow.ToString('o')
        CaptureStatus = $(if ($Warnings.Count) { 'Partial capture' } else { 'Captured; review pending' })
        EvidenceHash = $hash
        PreviousEvidenceHash = $(if ($Previous) { $Previous.EvidenceHash } else { $null })
        PreviousRevision = $(if ($Previous) { $Previous.WorkItem.rev } else { $null })
        EvidenceChanged = (-not $Previous -or $Previous.EvidenceHash -ne $hash)
        WorkItem = $WorkItem
        Comments = $Comments
        Attachments = $Attachments
        Warnings = $Warnings
    }
}

function Write-TaskSnapshot {
    param($Snapshot, [string]$Directory)
    $jsonPath = Join-Path $Directory 'source.json'
    $markdownPath = Join-Path $Directory 'source.md'
    $jsonTemp = "$jsonPath.$([Guid]::NewGuid().ToString('N')).tmp"
    $markdownTemp = "$markdownPath.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($jsonTemp, (ConvertTo-Json -InputObject $Snapshot -Depth 100) + "`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($markdownTemp, (Format-TaskSource -Snapshot $Snapshot), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($markdownTemp, $markdownPath, $true)
        [IO.File]::Move($jsonTemp, $jsonPath, $true)
    }
    finally {
        foreach ($temp in @($jsonTemp, $markdownTemp)) { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
    }
}

function Invoke-TaskCollection {
    param($Target, [string]$Root)
    $rootPath = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
    $directory = Join-Path $rootPath ".aw/tasks/$($Target.Id)"
    $previous = Read-PreviousTaskSnapshot -Target $Target -Directory $directory
    $workItem = Invoke-TaskRequest -Uri "$($Target.BaseUrl)/_apis/wit/workitems/$($Target.Id)?`$expand=all&api-version=7.1" -Org $Target.Organization
    if ([string]$workItem.id -ne $Target.Id -or -not $workItem.fields) { throw 'Unexpected work-item response; previous snapshot retained.' }
    $warnings = [System.Collections.Generic.List[string]]::new()
    $comments = @(Get-TaskComments -Target $Target -Warnings $warnings)
    [IO.Directory]::CreateDirectory((Join-Path $directory 'attachments')) | Out-Null
    $candidates = @(Get-TaskAttachments -WorkItem $workItem -Comments $comments)
    $attachments = @(Save-TaskAttachments -Candidates $candidates -Target $Target -Directory $directory -Warnings $warnings)
    $snapshot = New-TaskSnapshot -Target $Target -WorkItem $workItem -Comments $comments -Attachments $attachments -Warnings $warnings.ToArray() -Previous $previous
    Write-TaskSnapshot -Snapshot $snapshot -Directory $directory
    return [ordered]@{ Directory = $directory; CaptureStatus = $snapshot.CaptureStatus; Revision = $workItem.rev; Comments = $comments.Count; Attachments = $attachments.Count; EvidenceChanged = $snapshot.EvidenceChanged; Warnings = $warnings.ToArray() }
}