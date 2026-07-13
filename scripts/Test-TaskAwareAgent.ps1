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
    'agent_type\s*=\s*"luna_task"',
    'agent_type\s*=\s*"terra_worker"',
    'agent_type\s*=\s*"sol_specialist"',
    '<!-- END CODEX TASK-AWARE AGENT -->'
)

$expectedAgents = [ordered]@{
    'luna-task.toml' = [ordered]@{ Model = 'gpt-5.6-luna'; Effort = 'low'; Sandbox = 'read-only' }
    'terra-worker.toml' = [ordered]@{ Model = 'gpt-5.6-terra'; Effort = 'medium'; Sandbox = $null }
    'sol-specialist.toml' = [ordered]@{ Model = 'gpt-5.6-sol'; Effort = 'high'; Sandbox = 'read-only' }
}

foreach ($entry in $expectedAgents.GetEnumerator()) {
    $escapedModel = [regex]::Escape([string]$entry.Value.Model)
    $escapedEffort = [regex]::Escape([string]$entry.Value.Effort)
    $patterns = @(
        '(?m)^name\s*=\s*"[^\"]+"\s*$',
        '(?m)^description\s*=\s*"""',
        '(?m)^developer_instructions\s*=\s*"""',
        "(?m)^model\s*=\s*`"$escapedModel`"\s*$",
        "(?m)^model_reasoning_effort\s*=\s*`"$escapedEffort`"\s*$"
    )
    if ($entry.Value.Sandbox) {
        $escapedSandbox = [regex]::Escape([string]$entry.Value.Sandbox)
        $patterns += "(?m)^sandbox_mode\s*=\s*`"$escapedSandbox`"\s*$"
    }
    Assert-FileContains -Path (Join-Path $agentsPath $entry.Key) -Patterns $patterns
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
