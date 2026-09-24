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
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$policySource = Join-Path $repositoryRoot 'config/AGENTS.task-aware.md'
$agentsSource = Join-Path $repositoryRoot 'agents'
$rulesSource = Join-Path $repositoryRoot 'rules/full-admin.rules'
$configPath = Join-Path $CodexHome 'config.toml'
$agentsMdPath = Join-Path $CodexHome 'AGENTS.md'
$agentsPath = Join-Path $CodexHome 'agents'
$fullAdminRulePath = Join-Path $CodexHome 'rules/task-aware-full-admin.rules'
$utf8NoBomStrict = [System.Text.UTF8Encoding]::new($false, $true)

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    $failures.Add($Message)
}

function Assert-FileContains {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing file: $Path"
        return
    }
    $content = Get-Content -Raw -LiteralPath $Path
    foreach ($pattern in $Patterns) {
        if ($content -notmatch $pattern) {
            Add-Failure "Missing pattern '$pattern' in $Path"
        }
    }
}

function Assert-FileAbsent {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Add-Failure "Unexpected retired file: $Path"
    }
}

function Test-ByteArrayEqual {
    param(
        [Parameter(Mandatory)][byte[]]$Left,
        [Parameter(Mandatory)][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index += 1) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Assert-FileByteParity {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$InstalledPath,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Add-Failure "Missing $Label source: $SourcePath"
        return
    }
    if (-not (Test-Path -LiteralPath $InstalledPath -PathType Leaf)) {
        Add-Failure "Missing installed $($Label): $InstalledPath"
        return
    }
    if (-not (Test-ByteArrayEqual -Left ([IO.File]::ReadAllBytes($SourcePath)) -Right ([IO.File]::ReadAllBytes($InstalledPath)))) {
        Add-Failure "Installed $Label does not match source bytes: $Label"
    }
}

function Get-ManagedPolicyArtifact {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing managed policy file: $Path"
        return $null
    }

    try {
        [byte[]]$rawBytes = [IO.File]::ReadAllBytes($Path)
        $content = $utf8NoBomStrict.GetString($rawBytes)
    }
    catch {
        Add-Failure "Managed policy file is not valid UTF-8: $Path"
        return $null
    }

    $beginMarker = '<!-- BEGIN CODEX TASK-AWARE AGENT -->'
    $endMarker = '<!-- END CODEX TASK-AWARE AGENT -->'
    $beginPattern = '(?m)^' + [regex]::Escape($beginMarker) + '\r?$'
    $endPattern = '(?m)^' + [regex]::Escape($endMarker) + '\r?$'
    $beginMatches = [regex]::Matches($content, $beginPattern)
    $endMatches = [regex]::Matches($content, $endPattern)
    if ($beginMatches.Count -ne 1 -or $endMatches.Count -ne 1) {
        Add-Failure "Expected exactly one managed marker pair in $Path; found begin=$($beginMatches.Count) end=$($endMatches.Count)."
        return $null
    }

    $blockStart = $beginMatches[0].Index
    $endStart = $endMatches[0].Index
    if ($blockStart -ge $endStart) {
        Add-Failure "Managed markers are not one ordered begin/end pair in $Path."
        return $null
    }
    $blockEnd = $endStart + $endMatches[0].Length
    if ($blockEnd -lt $content.Length -and $content[$blockEnd] -eq [char]13) {
        $blockEnd += 1
    }
    if ($blockEnd -lt $content.Length -and $content[$blockEnd] -eq [char]10) {
        $blockEnd += 1
    }
    $blockText = $content.Substring($blockStart, $blockEnd - $blockStart)

    return [pscustomobject]@{
        Path = $Path
        RawBytes = $rawBytes
        BlockText = $blockText
        BlockBytes = $utf8NoBomStrict.GetBytes($blockText)
    }
}

function Assert-ManagedPolicyParity {
    param(
        [object]$SourceArtifact,
        [object]$LiveArtifact
    )

    if ($null -eq $SourceArtifact -or $null -eq $LiveArtifact) {
        return
    }
    if (-not (Test-ByteArrayEqual -Left $SourceArtifact.RawBytes -Right $LiveArtifact.BlockBytes)) {
        Add-Failure 'Managed Task-Aware policy source/live byte parity failed.'
    }
}

function Assert-ManagedPolicyContains {
    param(
        [object]$Artifact,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    if ($null -eq $Artifact) {
        return
    }
    foreach ($pattern in $Patterns) {
        if ($Artifact.BlockText -notmatch $pattern) {
            Add-Failure "Missing managed pattern '$pattern' in $($Artifact.Path)"
        }
    }
}

function Assert-ManagedPolicyExcludes {
    param(
        [object]$Artifact,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    if ($null -eq $Artifact) {
        return
    }
    foreach ($pattern in $Patterns) {
        if ($Artifact.BlockText -match $pattern) {
            Add-Failure "Forbidden managed pattern '$pattern' found in $($Artifact.Path)"
        }
    }
}

function Test-ManagedBlockMatches {
    param(
        [Parameter(Mandatory)][string]$BlockText,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($BlockText -notmatch $pattern) {
            return $false
        }
    }
    return $true
}

function Test-ManagedBlockExcludes {
    param(
        [Parameter(Mandatory)][string]$BlockText,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($BlockText -match $pattern) {
            return $false
        }
    }
    return $true
}

function Invoke-PolicyFaultInjection {
    param([object]$SourceArtifact)

    if ($null -eq $SourceArtifact) {
        Add-Failure 'Could not extract source policy for fault injection.'
        return
    }
    if (-not (Test-ManagedBlockMatches -BlockText $SourceArtifact.BlockText -Patterns $managedPolicyPatterns) -or
        -not (Test-ManagedBlockExcludes -BlockText $SourceArtifact.BlockText -Patterns $forbiddenPolicyPatterns)) {
        Add-Failure 'Source policy does not satisfy the managed policy contract before fault injection.'
        return
    }

    $withoutDeadline = $SourceArtifact.BlockText.Replace('HARD_DEADLINE', 'DEADLINE_REMOVED')
    if (Test-ManagedBlockMatches -BlockText $withoutDeadline -Patterns $managedPolicyPatterns) {
        Add-Failure 'Fault injection did not detect removed HARD_DEADLINE clauses.'
    }
    $withoutStalled = $SourceArtifact.BlockText.Replace('STALLED', 'LIFECYCLE_STOPPED')
    if (Test-ManagedBlockMatches -BlockText $withoutStalled -Patterns $managedPolicyPatterns) {
        Add-Failure 'Fault injection did not detect removed STALLED clauses.'
    }
    $withoutClassification = $SourceArtifact.BlockText.Replace(
        'Classification alone never authorizes or requires delegation',
        'Classification authorization removed'
    )
    if (Test-ManagedBlockMatches -BlockText $withoutClassification -Patterns $managedPolicyPatterns) {
        Add-Failure 'Fault injection did not detect removed classification-not-authorization clause.'
    }
    $withoutRequired = $SourceArtifact.BlockText.Replace('REQUIRED_ACCEPTANCE_CHECKS', 'REQUIRED_CHECKS_REMOVED')
    if (Test-ManagedBlockMatches -BlockText $withoutRequired -Patterns $managedPolicyPatterns) {
        Add-Failure 'Fault injection did not detect removed REQUIRED_ACCEPTANCE_CHECKS clauses.'
    }
    $withoutOptional = $SourceArtifact.BlockText.Replace('OPTIONAL_EVIDENCE', 'OPTIONAL_REMOVED')
    if (Test-ManagedBlockMatches -BlockText $withoutOptional -Patterns $managedPolicyPatterns) {
        Add-Failure 'Fault injection did not detect removed OPTIONAL_EVIDENCE clauses.'
    }
    $withoutStop = $SourceArtifact.BlockText.Replace('STOP_CONDITION', 'STOP_REMOVED')
    if (Test-ManagedBlockMatches -BlockText $withoutStop -Patterns $managedPolicyPatterns) {
        Add-Failure 'Fault injection did not detect removed STOP_CONDITION clauses.'
    }
    $withLegacyWait = $SourceArtifact.BlockText + [Environment]::NewLine + 'a tool-wait timeout is nonterminal: re-wait and do not interrupt'
    if (Test-ManagedBlockExcludes -BlockText $withLegacyWait -Patterns $forbiddenPolicyPatterns) {
        Add-Failure 'Fault injection did not reject the unbounded wait clause.'
    }
}

$managedPolicyPatterns = @(
    'Managed source: config/AGENTS\.task-aware\.md',
    'Task-aware delegation policy v3\.1',
    'Fix the request-mode authority and mutation boundary',
    'Delegation never expands the authority granted to the parent',
    'D1 uses `gpt-6-luna`, D2 uses `gpt-6-sol`',
    'The target parent is GPT-6 Astra',
    'D3/D4 use `gpt-6-astra`',
    'Children never delegate',
    'Classify capability first, then choose reasoning effort',
    'luna_task_medium',
    'astra_architect',
    'astra_architect_max',
    'D1 Low/Medium/High, D2 Medium/High, D3 High/xhigh, and D4 xhigh/Max',
    'D4 synthesis requires findings from at least two independent D3 work items',
    'same three-child limit',
    'NEEDS_INPUT',
    '### Decision order',
    'D0 always remains with the parent and never spawns',
    'Only after an affirmative spawn decision, choose role and effort',
    'Classification alone never authorizes or requires delegation',
    'any delegation gate fails, the parent retains ownership and executes directly',
    'Reasoning effort alone never expands a role''s permissions',
    'Administrator privilege gate',
    'ADMIN_AUTHORIZED: yes',
    'Never auto-promote an escalation',
    'REQUIRED_ACCEPTANCE_CHECKS',
    'OPTIONAL_EVIDENCE',
    'STOP_CONDITION',
    'EXPANSION_TRIGGER',
    'NO_PROGRESS_LIMIT',
    'HARD_DEADLINE',
    'SAFE_CANCELLATION',
    'Upper roles',
    '(?-i:\bSTALLED\b)',
    'Only a terminal child return may be validated and integrated'
)
$forbiddenPolicyPatterns = @(
    'tool-wait timeout is nonterminal: re-wait and do not interrupt',
    'After required checks pass, continue collecting any additional evidence available',
    'D1 default: call `spawn_agent`'
)

Assert-FileContains -Path $configPath -Patterns @(
    '(?m)^[ \t]*\[agents\][ \t]*(?:#[^\r\n]*)?\r?$',
    '(?m)^enabled\s*=\s*true\s*$',
    '(?m)^max_concurrent_threads_per_session\s*=\s*3\s*$'
)

$sourcePolicyArtifact = Get-ManagedPolicyArtifact -Path $policySource
$livePolicyArtifact = Get-ManagedPolicyArtifact -Path $agentsMdPath
Assert-ManagedPolicyParity -SourceArtifact $sourcePolicyArtifact -LiveArtifact $livePolicyArtifact
# Keep always-loaded guidance compact; do not cap the user's unmanaged text.
if ($null -ne $sourcePolicyArtifact -and $sourcePolicyArtifact.RawBytes.Length -gt 10240) {
    Add-Failure 'Managed policy exceeds the 10 KiB maintenance budget; consolidate existing rules before adding more.'
}
Assert-ManagedPolicyContains -Artifact $sourcePolicyArtifact -Patterns $managedPolicyPatterns
Assert-ManagedPolicyContains -Artifact $livePolicyArtifact -Patterns $managedPolicyPatterns
Assert-ManagedPolicyExcludes -Artifact $sourcePolicyArtifact -Patterns $forbiddenPolicyPatterns
Assert-ManagedPolicyExcludes -Artifact $livePolicyArtifact -Patterns $forbiddenPolicyPatterns
Invoke-PolicyFaultInjection -SourceArtifact $sourcePolicyArtifact

$expectedAgents = [ordered]@{
    'luna-task.toml' = [ordered]@{ Name = 'luna_task'; Model = 'gpt-6-luna'; Effort = 'low'; Sandbox = 'read-only'; Approval = 'never' }
    'luna-task-medium.toml' = [ordered]@{ Name = 'luna_task_medium'; Model = 'gpt-6-luna'; Effort = 'medium'; Sandbox = 'read-only'; Approval = 'never' }
    'luna-task-max.toml' = [ordered]@{ Name = 'luna_task_max'; Model = 'gpt-6-luna'; Effort = 'high'; Sandbox = 'read-only'; Approval = 'never' }
    'terra-worker.toml' = [ordered]@{ Name = 'terra_worker'; Model = 'gpt-6-sol'; Effort = 'medium'; Sandbox = $null; Approval = 'never' }
    'terra-worker-max.toml' = [ordered]@{ Name = 'terra_worker_max'; Model = 'gpt-6-sol'; Effort = 'high'; Sandbox = $null; Approval = 'never' }
    'sol-specialist.toml' = [ordered]@{ Name = 'sol_specialist'; Model = 'gpt-6-astra'; Effort = 'high'; Sandbox = 'read-only'; Approval = 'never' }
    'sol-specialist-max.toml' = [ordered]@{ Name = 'sol_specialist_max'; Model = 'gpt-6-astra'; Effort = 'xhigh'; Sandbox = 'read-only'; Approval = 'never' }
    'astra-architect.toml' = [ordered]@{ Name = 'astra_architect'; Model = 'gpt-6-astra'; Effort = 'xhigh'; Sandbox = 'read-only'; Approval = 'never' }
    'astra-architect-max.toml' = [ordered]@{ Name = 'astra_architect_max'; Model = 'gpt-6-astra'; Effort = 'max'; Sandbox = 'read-only'; Approval = 'never' }
    'sol-admin-max.toml' = [ordered]@{ Name = 'sol_admin_max'; Model = 'gpt-6-astra'; Effort = 'max'; Sandbox = 'danger-full-access'; Approval = 'on-request' }
}

foreach ($entry in $expectedAgents.GetEnumerator()) {
    $agentFile = $entry.Key
    $definition = $entry.Value
    $escapedName = [regex]::Escape([string]$definition.Name)
    $escapedModel = [regex]::Escape([string]$definition.Model)
    $escapedEffort = [regex]::Escape([string]$definition.Effort)
    $escapedSandbox = [regex]::Escape([string]$definition.Sandbox)
    $escapedApproval = [regex]::Escape([string]$definition.Approval)
    $installedPath = Join-Path $agentsPath $agentFile
    $sourcePath = Join-Path $agentsSource $agentFile
    $patterns = @(
        "(?m)^name\s*=\s*""$escapedName""\s*$",
        '(?m)^description\s*=\s*"""',
        '(?m)^developer_instructions\s*=\s*"""',
        "(?m)^model\s*=\s*""$escapedModel""\s*$",
        "(?m)^model_reasoning_effort\s*=\s*""$escapedEffort""\s*$",
        "(?m)^approval_policy\s*=\s*""$escapedApproval""\s*$"
    )
    if ($null -ne $definition.Sandbox) {
        $patterns += "(?m)^sandbox_mode\s*=\s*""$escapedSandbox""\s*$"
    }
    elseif ((Test-Path -LiteralPath $installedPath) -and
        (Get-Content -Raw -LiteralPath $installedPath) -match '(?m)^\s*sandbox_mode\s*=') {
        Add-Failure "D2 role must inherit the parent sandbox: $agentFile"
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
    Assert-FileContains -Path $installedPath -Patterns $patterns
    Assert-FileByteParity -SourcePath $sourcePath -InstalledPath $installedPath -Label "agent $agentFile"
}

foreach ($agentFile in @(
        'luna-task.toml',
        'luna-task-medium.toml',
        'astra-architect.toml',
        'astra-architect-max.toml',
        'luna-task-max.toml',
        'terra-worker.toml',
        'terra-worker-max.toml',
        'sol-specialist.toml',
        'sol-specialist-max.toml'
    )) {
    Assert-FileContains -Path (Join-Path $agentsPath $agentFile) -Patterns @('Never invoke or request sudo')
}
Assert-FileContains -Path (Join-Path $agentsPath 'sol-admin-max.toml') -Patterns @(
    'ADMIN_AUTHORIZED: yes',
    'Before every command that uses sudo',
    'never use sudo -S',
    'This role definition alone is not root or an administrator token'
)

Assert-FileContains -Path $fullAdminRulePath -Patterns @(
    'decision\s*=\s*"prompt"',
    '"sudo"',
    '"doas"',
    '"pkexec"',
    '"su"',
    '"runas"',
    '"gsudo"',
    '"Start-Process"',
    'explicit sol_admin_max full-admin gate'
)
Assert-FileByteParity -SourcePath $rulesSource -InstalledPath $fullAdminRulePath -Label 'full-admin rule'

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
        $execPolicyOutput = (& $codex.Source execpolicy check --pretty --rules $fullAdminRulePath -- sudo -n true | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw "codex execpolicy check failed with exit code $LASTEXITCODE for $fullAdminRulePath"
        }
        try {
            $execPolicyReport = $execPolicyOutput | ConvertFrom-Json -Depth 20
        }
        catch {
            throw "codex execpolicy check did not return valid JSON: $($execPolicyOutput.Trim())"
        }
        if ($execPolicyReport.decision -ne 'prompt') {
            throw "Full-admin execpolicy did not prompt for sudo: $($execPolicyOutput.Trim())"
        }
        Write-Host "Full-admin execpolicy prompt passed for CODEX_HOME=$($env:CODEX_HOME)."

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
