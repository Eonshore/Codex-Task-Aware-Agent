[CmdletBinding()]
param(
    [string]$CodexHome = $(
        if ($env:CODEX_HOME) { $env:CODEX_HOME }
        else { Join-Path $HOME '.codex' }
    ),
    [switch]$SkipRuntime
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-FileContains {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $failures.Add("Missing file: $Path")
        return
    }

    $content = Get-Content -Raw -LiteralPath $Path
    foreach ($pattern in $Patterns) {
        if ($content -notmatch $pattern) {
            $failures.Add("Missing pattern '$pattern' in $Path")
        }
    }
}

$configPath = Join-Path $CodexHome 'config.toml'
$agentsMdPath = Join-Path $CodexHome 'AGENTS.md'
$agentsPath = Join-Path $CodexHome 'agents'

Assert-FileContains -Path $configPath -Patterns @(
    '(?m)^\[features\]\s*$',
    '(?m)^multi_agent\s*=\s*true\s*$',
    '(?m)^\[agents\]\s*$',
    '(?m)^max_threads\s*=\s*4\s*$',
    '(?m)^max_depth\s*=\s*1\s*$'
)

Assert-FileContains -Path $agentsMdPath -Patterns @(
    '<!-- BEGIN CODEX TASK-AWARE AGENT -->',
    'Task-aware delegation policy',
    '<!-- END CODEX TASK-AWARE AGENT -->'
)

$expectedAgents = [ordered]@{
    'luna-task.toml' = 'gpt-5.6-luna'
    'terra-worker.toml' = 'gpt-5.6-terra'
    'sol-specialist.toml' = 'gpt-5.6-sol'
}

foreach ($entry in $expectedAgents.GetEnumerator()) {
    $escapedModel = [regex]::Escape([string]$entry.Value)
    Assert-FileContains -Path (Join-Path $agentsPath $entry.Key) -Patterns @(
        '(?m)^name\s*=\s*"[^\"]+"\s*$',
        '(?m)^description\s*=\s*"""',
        '(?m)^developer_instructions\s*=\s*"""',
        "(?m)^model\s*=\s*`"$escapedModel`"\s*$"
    )
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($codex -and -not $SkipRuntime) {
    & $codex.Source doctor --summary --no-color --ascii
    if ($LASTEXITCODE -ne 0) {
        throw "codex doctor failed with exit code $LASTEXITCODE"
    }
}
elseif (-not $codex -and -not $SkipRuntime) {
    Write-Warning 'codex was not found; file validation passed but runtime validation was skipped.'
}

Write-Host 'Task-Aware Agent validation passed.'
