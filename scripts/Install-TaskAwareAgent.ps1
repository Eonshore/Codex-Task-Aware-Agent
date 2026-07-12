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
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Values
    )

    $escapedSection = [regex]::Escape($Section)
    $headerPattern = "(?m)^\[$escapedSection\]\s*$"
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
    $nextHeader = [regex]::Match($remaining, '(?m)^\[[^\r\n]+\]\s*$')
    $bodyLength = if ($nextHeader.Success) { $nextHeader.Index } else { $remaining.Length }
    $body = $remaining.Substring(0, $bodyLength)

    foreach ($entry in $Values.GetEnumerator()) {
        $escapedKey = [regex]::Escape([string]$entry.Key)
        $keyPattern = "(?m)^$escapedKey\s*=.*$"
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

function Set-TopLevelTomlValue {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $firstSection = [regex]::Match($Content, '(?m)^\[[^\r\n]+\]\s*$')
    $headLength = if ($firstSection.Success) { $firstSection.Index } else { $Content.Length }
    $head = $Content.Substring(0, $headLength)
    $tail = $Content.Substring($headLength)
    $escapedKey = [regex]::Escape($Key)
    $keyPattern = "(?m)^$escapedKey\s*=.*$"
    $replacement = "$Key = $Value"

    if ([regex]::IsMatch($head, $keyPattern)) {
        $head = [regex]::Replace($head, $keyPattern, $replacement, 1)
    }
    else {
        $head = $head.TrimEnd() + "`n$replacement`n`n"
    }

    return $head + $tail
}

if (-not $PSCmdlet.ShouldProcess($CodexHome, 'Install Codex Task-Aware Agent configuration')) {
    return
}

New-Item -ItemType Directory -Force -Path $CodexHome, $AgentsPath, $BackupPath | Out-Null

Backup-IfPresent -Path $ConfigPath
Backup-IfPresent -Path $AgentsMdPath
Get-ChildItem -LiteralPath $AgentsSource -Filter '*.toml' | ForEach-Object {
    Backup-IfPresent -Path (Join-Path $AgentsPath $_.Name)
}

$config = if (Test-Path -LiteralPath $ConfigPath) {
    Get-Content -Raw -LiteralPath $ConfigPath
}
else { '' }

$config = Set-TomlSectionValues -Content $config -Section 'features' -Values ([ordered]@{
    multi_agent = 'true'
})
$config = Set-TomlSectionValues -Content $config -Section 'agents' -Values ([ordered]@{
    max_threads = '4'
    max_depth = '1'
})

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

Copy-Item -Path (Join-Path $AgentsSource '*.toml') -Destination $AgentsPath -Force

Write-Host "Installed Task-Aware Agent configuration in $CodexHome"
Write-Host "Backup: $BackupPath"
Write-Host 'Restart Codex or start a new task to load the updated instruction chain.'
