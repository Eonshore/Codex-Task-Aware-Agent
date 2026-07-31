[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CodexHome = $(
        if ($env:CODEX_HOME) { $env:CODEX_HOME }
        else { Join-Path $HOME '.codex' }
    ),
    [switch]$SetSolDefault,
    [switch]$EnableFullAccess
)

$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$AgentsSource = Join-Path $RepositoryRoot 'agents'
$PolicySource = Join-Path $RepositoryRoot 'config/AGENTS.task-aware.md'
$ConfigPath = Join-Path $CodexHome 'config.toml'
$AgentsPath = Join-Path $CodexHome 'agents'
$AgentsMdPath = Join-Path $CodexHome 'AGENTS.md'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupPath = Join-Path $CodexHome "task-aware-backups/$Timestamp"
$BackupSuffix = 0

while (Test-Path -LiteralPath $BackupPath) {
    $BackupSuffix++
    $BackupPath = Join-Path $CodexHome "task-aware-backups/$Timestamp-$BackupSuffix"
}

function Backup-IfPresent {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $relative = [IO.Path]::GetRelativePath($CodexHome, $Path)
    $destination = Join-Path $BackupPath $relative
    $destinationDirectory = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Force
}

function Set-TomlSectionValues {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Values
    )

    $escapedSection = [regex]::Escape($Section)
    $headerPattern = "(?m)^[ \t]*\[$escapedSection\][ \t]*(?:#[^\r\n]*)?\r?$"
    $header = [regex]::Match($Content, $headerPattern)

    if (-not $header.Success) {
        $block = "`n[$Section]`n"
        foreach ($entry in $Values.GetEnumerator()) {
            $block += "$($entry.Key) = $($entry.Value)`n"
        }
        return $Content.TrimEnd() + "`n" + $block
    }

    $bodyStart = $header.Index + $header.Length
    $remaining = $Content.Substring($bodyStart)
    $nextHeader = [regex]::Match($remaining, '(?m)^[ \t]*\[[^\]\r\n]+\][ \t]*(?:#[^\r\n]*)?\r?$')
    $bodyLength = if ($nextHeader.Success) { $nextHeader.Index } else { $remaining.Length }
    $body = $remaining.Substring(0, $bodyLength)

    foreach ($entry in $Values.GetEnumerator()) {
        $escapedKey = [regex]::Escape([string]$entry.Key)
        $keyPattern = "(?m)^[ \t]*$escapedKey[ \t]*=.*$"
        $replacement = "$($entry.Key) = $($entry.Value)"
        if ([regex]::IsMatch($body, $keyPattern)) {
            $body = [regex]::Replace($body, $keyPattern, $replacement, 1)
        }
        else {
            $body = $body.TrimEnd() + "`n$replacement`n"
        }
    }

    return $Content.Substring(0, $bodyStart) + $body + $remaining.Substring($bodyLength)
}

function Remove-TomlSectionKeys {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string[]]$Keys
    )

    $escapedSection = [regex]::Escape($Section)
    $headerPattern = "(?m)^[ \t]*\[$escapedSection\][ \t]*(?:#[^\r\n]*)?\r?$"
    $header = [regex]::Match($Content, $headerPattern)
    if (-not $header.Success) { return $Content }

    $bodyStart = $header.Index + $header.Length
    $remaining = $Content.Substring($bodyStart)
    $nextHeader = [regex]::Match($remaining, '(?m)^[ \t]*\[[^\]\r\n]+\][ \t]*(?:#[^\r\n]*)?\r?$')
    $bodyLength = if ($nextHeader.Success) { $nextHeader.Index } else { $remaining.Length }
    $body = $remaining.Substring(0, $bodyLength)

    foreach ($key in $Keys) {
        $escapedKey = [regex]::Escape($key)
        $body = [regex]::Replace(
            $body,
            "(?m)^[ \t]*$escapedKey[ \t]*=.*(?:\r?\n|$)",
            ''
        )
    }

    return $Content.Substring(0, $bodyStart) + $body + $remaining.Substring($bodyLength)
}

function Set-TopLevelTomlValue {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $firstSection = [regex]::Match($Content, '(?m)^[ \t]*\[[^\]\r\n]+\][ \t]*(?:#[^\r\n]*)?\r?$')
    $headLength = if ($firstSection.Success) { $firstSection.Index } else { $Content.Length }
    $head = $Content.Substring(0, $headLength)
    $tail = $Content.Substring($headLength)
    $escapedKey = [regex]::Escape($Key)
    $keyPattern = "(?m)^[ \t]*$escapedKey[ \t]*=.*$"
    $replacement = "$Key = $Value"

    if ([regex]::IsMatch($head, $keyPattern)) {
        $head = [regex]::Replace($head, $keyPattern, $replacement, 1)
    }
    else {
        $head = $head.TrimEnd() + "`n$replacement`n`n"
    }

    return $head + $tail
}

$expectedAgentFiles = @(
    'luna-task.toml',
    'luna-task-max.toml',
    'terra-worker.toml',
    'terra-worker-max.toml',
    'sol-specialist.toml',
    'sol-specialist-max.toml'
)
$retiredAgentFiles = @('luna-task-high.toml', 'terra-worker-high.toml')
if (-not (Test-Path -LiteralPath $PolicySource -PathType Leaf)) {
    throw "Missing policy source: $PolicySource"
}
foreach ($agentFile in $expectedAgentFiles) {
    $agentSourcePath = Join-Path $AgentsSource $agentFile
    if (-not (Test-Path -LiteralPath $agentSourcePath -PathType Leaf)) {
        throw "Missing agent source: $agentSourcePath"
    }
}

if ($EnableFullAccess -and (Test-Path -LiteralPath $ConfigPath)) {
    $existingConfig = Get-Content -Raw -LiteralPath $ConfigPath
    if ($existingConfig -match '(?m)^[ \t]*default_permissions[ \t]*=') {
        throw 'Cannot use -EnableFullAccess while config.toml defines default_permissions. Remove one permission system before retrying.'
    }
}

if (Test-Path -LiteralPath $AgentsMdPath) {
    $existingAgentsMd = Get-Content -Raw -LiteralPath $AgentsMdPath
    $beginMarker = '<!-- BEGIN CODEX TASK-AWARE AGENT -->'
    $endMarker = '<!-- END CODEX TASK-AWARE AGENT -->'
    $beginCount = [regex]::Matches($existingAgentsMd, [regex]::Escape($beginMarker)).Count
    $endCount = [regex]::Matches($existingAgentsMd, [regex]::Escape($endMarker)).Count
    $completeBlock = "(?s)" + [regex]::Escape($beginMarker) + ".*?" + [regex]::Escape($endMarker)
    if ($beginCount -ne $endCount -or $beginCount -gt 1 -or ($beginCount -eq 1 -and $existingAgentsMd -notmatch $completeBlock)) {
        throw 'AGENTS.md contains malformed or duplicate Task-Aware Agent markers. Repair the marker block before retrying.'
    }
}

if (-not $PSCmdlet.ShouldProcess($CodexHome, 'Install Codex Task-Aware Agent configuration')) {
    return
}

New-Item -ItemType Directory -Force -Path $CodexHome, $AgentsPath, $BackupPath | Out-Null

Backup-IfPresent -Path $ConfigPath
Backup-IfPresent -Path $AgentsMdPath
foreach ($agentFile in $expectedAgentFiles) {
    Backup-IfPresent -Path (Join-Path $AgentsPath $agentFile)
}
foreach ($agentFile in $retiredAgentFiles) {
    Backup-IfPresent -Path (Join-Path $AgentsPath $agentFile)
}

$config = if (Test-Path -LiteralPath $ConfigPath) {
    Get-Content -Raw -LiteralPath $ConfigPath
}
else { '' }

$config = Set-TomlSectionValues -Content $config -Section 'agents' -Values ([ordered]@{
    enabled = 'true'
    max_concurrent_threads_per_session = '3'
})
$config = Remove-TomlSectionKeys -Content $config -Section 'agents' -Keys @(
    'max_threads',
    'max_depth'
)
$config = Remove-TomlSectionKeys -Content $config -Section 'features' -Keys @(
    'multi_agent'
)

if ($SetSolDefault) {
    $config = Set-TopLevelTomlValue -Content $config -Key 'model' -Value '"gpt-5.6-sol"'
    $config = Set-TopLevelTomlValue -Content $config -Key 'model_reasoning_effort' -Value '"xhigh"'
}

if ($EnableFullAccess) {
    $config = Set-TopLevelTomlValue -Content $config -Key 'approval_policy' -Value '"never"'
    $config = Set-TopLevelTomlValue -Content $config -Key 'sandbox_mode' -Value '"danger-full-access"'
}

Set-Content -LiteralPath $ConfigPath -Value $config.TrimEnd() -Encoding utf8

$policy = Get-Content -Raw -LiteralPath $PolicySource
$agentsMd = if (Test-Path -LiteralPath $AgentsMdPath) {
    Get-Content -Raw -LiteralPath $AgentsMdPath
}
else { '' }

$begin = '<!-- BEGIN CODEX TASK-AWARE AGENT -->'
$end = '<!-- END CODEX TASK-AWARE AGENT -->'
$existingBlock = "(?s)" + [regex]::Escape($begin) + ".*?" + [regex]::Escape($end)
if ([regex]::IsMatch($agentsMd, $existingBlock)) {
    $agentsMd = [regex]::Replace($agentsMd, $existingBlock, $policy.Trim())
}
else {
    $agentsMd = $agentsMd.TrimEnd() + "`n`n" + $policy.Trim() + "`n"
}
Set-Content -LiteralPath $AgentsMdPath -Value $agentsMd.TrimStart() -Encoding utf8

foreach ($agentFile in $expectedAgentFiles) {
    Copy-Item -LiteralPath (Join-Path $AgentsSource $agentFile) -Destination $AgentsPath -Force
}
foreach ($agentFile in $retiredAgentFiles) {
    $retiredPath = Join-Path $AgentsPath $agentFile
    if (Test-Path -LiteralPath $retiredPath -PathType Leaf) {
        Remove-Item -LiteralPath $retiredPath -Force
    }
}

Write-Host "Installed Task-Aware Agent configuration in $CodexHome"
Write-Host "Backup: $BackupPath"
Write-Host 'Restart Codex or start a new task to load the updated instruction chain.'
