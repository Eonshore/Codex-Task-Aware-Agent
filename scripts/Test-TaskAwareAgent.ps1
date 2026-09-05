[CmdletBinding()]
param(
    [string]$CodexHome = $(
        if ($env:CODEX_HOME) { $env:CODEX_HOME }
        else { Join-Path $HOME '.codex' }
    ),
    [switch]$SkipRuntime,
    [switch]$ConfigOnlyRuntime
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

function Assert-FileAbsent {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        $failures.Add("Unexpected retired file: $Path")
    }
}

$configPath = Join-Path $CodexHome 'config.toml'
$agentsMdPath = Join-Path $CodexHome 'AGENTS.md'
$agentsPath = Join-Path $CodexHome 'agents'

Assert-FileContains -Path $configPath -Patterns @(
    '(?m)^[ \t]*\[agents\][ \t]*(?:#[^\r\n]*)?\r?$',
    '(?m)^enabled\s*=\s*true\s*$',
    '(?m)^max_concurrent_threads_per_session\s*=\s*3\s*$'
)

Assert-FileContains -Path $agentsMdPath -Patterns @(
    '<!-- BEGIN CODEX TASK-AWARE AGENT -->',
    'Task-aware delegation policy',
    'agent_type\s*=\s*"luna_task"',
    'agent_type\s*=\s*"luna_task_max"',
    'agent_type\s*=\s*"luna_task_medium"',
    'agent_type\s*=\s*"astra_architect"',
    'agent_type\s*=\s*"astra_architect_max"',
    'agent_type\s*=\s*"terra_worker"',
    'agent_type\s*=\s*"terra_worker_max"',
    'agent_type\s*=\s*"sol_specialist"',
    'agent_type\s*=\s*"sol_specialist_max"',
    'Classify capability first, then choose reasoning effort',
    'Higher effort never expands a role''s permissions',
    'The target parent is GPT-6 Astra',
    'Children never delegate',
    'D4 synthesis requires findings from at least two independent D3 work items',
    'same three-child limit',
    'For D1 Medium, state what reconciliation makes Low insufficient',
    'Keep verification proportional to the change',
    'All nine child roles use gpt-6-astra with low, medium, high, xhigh, or max reasoning',
    'D1 Low/Medium/High, D2 Medium/High, D3 High/xhigh, and D4 xhigh/Max',
    'D3 uses Astra High by default and Astra xhigh',
    'The luna, terra, sol, and _max names no longer specify the model or effort',
    'include the concrete reason the standard role',
    'explain why Medium is more error-prone',
    'for D3, explain why High is insufficient',
    'bounded read-only investigation or verification',
    'Inputs, the\s+output contract, and the success condition must be explicit',
    'State-changing implementation',
    'tool-heavy multi-step work',
    'requires ordinary judgment',
    'Do not split an atomic D0 item solely to use a lower effort',
    'Do not route an obvious D2 or D3 item through a lower-class role',
    'fork_turns\s*=\s*"none"',
    'packet must explicitly tell the child not to delegate',
    '<!-- END CODEX TASK-AWARE AGENT -->'
)

$expectedAgents = [ordered]@{
    'luna-task-medium.toml' = [ordered]@{ Name = 'luna_task_medium'; Model = 'gpt-6-astra'; Effort = 'medium'; Sandbox = 'read-only' }
    'astra-architect.toml' = [ordered]@{ Name = 'astra_architect'; Model = 'gpt-6-astra'; Effort = 'xhigh'; Sandbox = 'read-only' }
    'astra-architect-max.toml' = [ordered]@{ Name = 'astra_architect_max'; Model = 'gpt-6-astra'; Effort = 'max'; Sandbox = 'read-only' }
    'luna-task.toml' = [ordered]@{ Name = 'luna_task'; Model = 'gpt-6-astra'; Effort = 'low'; Sandbox = 'read-only' }
    'luna-task-max.toml' = [ordered]@{ Name = 'luna_task_max'; Model = 'gpt-6-astra'; Effort = 'high'; Sandbox = 'read-only' }
    'terra-worker.toml' = [ordered]@{ Name = 'terra_worker'; Model = 'gpt-6-astra'; Effort = 'medium'; Sandbox = $null }
    'terra-worker-max.toml' = [ordered]@{ Name = 'terra_worker_max'; Model = 'gpt-6-astra'; Effort = 'high'; Sandbox = $null }
    'sol-specialist.toml' = [ordered]@{ Name = 'sol_specialist'; Model = 'gpt-6-astra'; Effort = 'high'; Sandbox = 'read-only' }
    'sol-specialist-max.toml' = [ordered]@{ Name = 'sol_specialist_max'; Model = 'gpt-6-astra'; Effort = 'xhigh'; Sandbox = 'read-only' }
}

foreach ($entry in $expectedAgents.GetEnumerator()) {
    $escapedModel = [regex]::Escape([string]$entry.Value.Model)
    $escapedEffort = [regex]::Escape([string]$entry.Value.Effort)
    $escapedName = [regex]::Escape([string]$entry.Value.Name)
    $patterns = @(
        "(?m)^name\s*=\s*`"$escapedName`"\s*$",
        '(?m)^description\s*=\s*"""',
        '(?m)^developer_instructions\s*=\s*"""',
        "(?m)^model\s*=\s*`"$escapedModel`"\s*$",
        "(?m)^model_reasoning_effort\s*=\s*`"$escapedEffort`"\s*$"
    )
    if ($entry.Value.Sandbox) {
        $escapedSandbox = [regex]::Escape([string]$entry.Value.Sandbox)
        $patterns += "(?m)^sandbox_mode\s*=\s*`"$escapedSandbox`"\s*$"
    }
    if ($entry.Key -eq 'luna-task.toml') {
        $patterns += 'Use as the default for compact, homogeneous D1'
        $patterns += 'bounded read-only investigation or'
        $patterns += 'fixed inputs, an explicit output contract'
        $patterns += 'success condition'
        $patterns += 'Do not use for material judgment, broad investigation, or state changes'
    }
    elseif ($entry.Key -eq 'luna-task-medium.toml') {
        $patterns += 'bounded D1 work with fixed inputs'
        $patterns += 'modest reconciliation across files or'
        $patterns += 'objective success condition'
        $patterns += 'Do not use for material judgment, broad investigation, or state changes'
        $patterns += 'Do not broaden scope or delegate'
    }
    elseif ($entry.Key -eq 'luna-task-max.toml') {
        $patterns += 'D1 work that remains deterministic, read-only, and objectively'
        $patterns += 'dense cross-checking across heterogeneous inputs'
        $patterns += 'Do not use for material judgment, broad investigation, or state changes'
        $patterns += 'Use High reasoning for completeness and cross-checking'
        $patterns += 'not to broaden the task''s\s+capability boundary'
    }
    elseif ($entry.Key -eq 'terra-worker.toml') {
        $patterns += 'Use as the default for bounded D2 state-changing implementation'
        $patterns += 'tool-heavy\s+multi-step work'
        $patterns += 'requires\s+ordinary\s+judgment'
    }
    elseif ($entry.Key -eq 'terra-worker-max.toml') {
        $patterns += 'D2 work that stays within ordinary engineering judgment'
        $patterns += 'many\s+coupled constraints'
        $patterns += 'Do not use for unresolved architectural trade-offs'
        $patterns += 'Use High reasoning for coupled constraints, edge cases, and verification'
        $patterns += 'not to\s+broaden the task''s capability boundary'
    }
    elseif ($entry.Key -eq 'sol-specialist-max.toml') {
        $patterns += 'D3 work when both uncertainty and consequence are high'
        $patterns += 'security-sensitive trade-offs'
        $patterns += 'reasoning variance'
    }
    elseif ($entry.Key -eq 'sol-specialist.toml') {
        $patterns += 'Use as the default for one bounded D3'
        $patterns += 'Prefer sol_specialist_max when uncertainty and consequence are both'
    }
    elseif ($entry.Key -in @('astra-architect.toml', 'astra-architect-max.toml')) {
        $patterns += 'bounded D4 synthesis'
        $patterns += 'at least two independent D3'
        $patterns += 'read-only synthesis role; the parent owns orchestration'
        $patterns += 'NEEDS_INPUT'
        $patterns += 'Do not repeat completed investigations'
        $patterns += 'Do not delegate'
        $patterns += 'Do not modify files or external state'
    }
    Assert-FileContains -Path (Join-Path $agentsPath $entry.Key) -Patterns $patterns
}

Assert-FileAbsent -Path (Join-Path $agentsPath 'luna-task-high.toml')
Assert-FileAbsent -Path (Join-Path $agentsPath 'terra-worker-high.toml')

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($codex -and -not $SkipRuntime) {
    $previousCodexHome = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = [IO.Path]::GetFullPath($CodexHome)
        if ($ConfigOnlyRuntime) {
            $doctorOutput = (& $codex.Source --strict-config doctor --json --no-color | Out-String)
            $doctorExitCode = $LASTEXITCODE
            try {
                $doctorReport = $doctorOutput | ConvertFrom-Json -Depth 20
            }
            catch {
                throw "codex doctor did not return valid JSON for CODEX_HOME=$($env:CODEX_HOME): $($doctorOutput.Trim())"
            }

            $configCheck = $doctorReport.checks.'config.load'
            if (-not $configCheck -or $configCheck.status -ne 'ok') {
                throw "Codex strict config load failed for CODEX_HOME=$($env:CODEX_HOME) (doctor exit $doctorExitCode)."
            }
            Write-Host "Codex strict config load passed for CODEX_HOME=$($env:CODEX_HOME)."
        }
        else {
            & $codex.Source --strict-config doctor --summary --no-color --ascii
            if ($LASTEXITCODE -ne 0) {
                throw "codex doctor failed with exit code $LASTEXITCODE for CODEX_HOME=$($env:CODEX_HOME)"
            }
        }
    }
    finally {
        if ($null -eq $previousCodexHome) {
            Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
        }
        else {
            $env:CODEX_HOME = $previousCodexHome
        }
    }
}
elseif (-not $codex -and -not $SkipRuntime) {
    Write-Warning 'codex was not found; file validation passed but runtime validation was skipped.'
}

$global:LASTEXITCODE = 0
Write-Host 'Task-Aware Agent validation passed.'
