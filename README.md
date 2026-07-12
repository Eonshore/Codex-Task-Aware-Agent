# Codex Task-Aware Agent

Codex の親エージェントがタスクを難易度別に分類し、必要な場合だけ低コストな
カスタムエージェントへ委譲するための設定一式です。

目的は、サブエージェントが親の高い推論強度をそのまま継承して消費量が膨らむ
ことを避けつつ、メインスレッドのコンテキスト汚染を抑えることです。

## ルーティング

| 難易度 | 対象 | 実行役 |
| --- | --- | --- |
| D0 | 単純で明確な1工程 | 親が直接処理 |
| D1 | 抽出、分類、変換、反復チェック | `luna_task` / Luna Low |
| D2 | 境界が明確な調査、通常実装、検証 | `terra_worker` / Terra Medium |
| D3 | 曖昧、高リスク、複数領域、設計判断 | `sol_specialist` / Sol High |
| D4 | 独立したD3タスクが複数 | 親が分割・統合 |

子エージェントの再帰委譲は無効化し、同時実行は親から直接の最大3子を基本と
します。

## 内容

- `config/AGENTS.task-aware.md`: グローバル指示へ追加するルーティング規則
- `config/config.task-aware.toml`: `config.toml` へ統合する設定例
- `agents/*.toml`: Luna、Terra、Solの役割別エージェント
- `scripts/Install-TaskAwareAgent.ps1`: バックアップ付き導入スクリプト
- `scripts/Test-TaskAwareAgent.ps1`: 配置とCodex設定の検証スクリプト
- `scripts/install-task-aware-agent.sh`: Linux向けのバックアップ付き導入スクリプト
- `scripts/test-task-aware-agent.sh`: Linux向けの配置とCodex設定の検証スクリプト

## 導入

PowerShell 7以降で実行します。

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1
```

Solを親の既定モデルにする場合:

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1 -SetSolDefault
```

フルアクセスも明示的に有効化する場合:

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1 -SetSolDefault -EnableFullAccess
```

LinuxではBash版を実行します。

```bash
./scripts/install-task-aware-agent.sh
```

Solを親の既定モデルにする場合:

```bash
./scripts/install-task-aware-agent.sh --set-sol-default
```

フルアクセスも明示的に有効化する場合:

```bash
./scripts/install-task-aware-agent.sh --set-sol-default --enable-full-access
```

別のCodexホームへ導入する場合は、`CODEX_HOME` 環境変数、または
`--codex-home PATH` を指定できます。

PowerShellの `-EnableFullAccess` とLinux版の `--enable-full-access` は、
`approval_policy = "never"` と `sandbox_mode = "danger-full-access"` を設定します。
信頼できる環境でのみ使用してください。

既存ファイルは `$CODEX_HOME/task-aware-backups/<timestamp>/` へ退避されます。
`CODEX_HOME` が未設定の場合は `~/.codex` を使用します。

## 検証

```powershell
pwsh -File .\scripts\Test-TaskAwareAgent.ps1
```

Linuxでは次のコマンドで検証します。

```bash
./scripts/test-task-aware-agent.sh
```

導入後はCodexを再起動するか、新しいタスクを開始してください。`AGENTS.md` の
指示チェーンは新しい実行の開始時に構築されます。

## Ultraについて

Codexのモデル選択画面でUltraを選択した場合、親はUltraで難易度判定と統合を
行い、子はこのリポジトリで指定したLuna/Terra/Solへ固定されます。

Codex CLIのバージョンによっては、モデル一覧にUltraが表示されても
`config.toml` の `model_reasoning_effort = "ultra"` を受理しません。そのため導入
スクリプトは、Solの既定値を設定する場合も互換性の高い `xhigh` を使用します。
Ultraは対応クライアントのモデル選択画面から選択してください。

## 設計上の注意

- サブエージェントはメインスレッドのノイズを減らしますが、総トークン量が必ず
  減るわけではありません。
- 並列化するのは、独立して進められる読み取り、調査、テスト、要約を優先します。
- 同じファイルや状態を更新する書き込みエージェントは1つに限定します。
- 安価な役割から上位役割へ移すのは、具体的な根拠を伴う
  `NEEDS_ESCALATION` が返された場合だけです。

## 参考資料

- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents?surface=app)
- [Models](https://learn.chatgpt.com/docs/models)
- [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
