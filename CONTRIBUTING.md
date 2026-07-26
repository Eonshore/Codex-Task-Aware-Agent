# コントリビューション

issue や pull request を歓迎します。変更は、既存の task routing contract と Windows/Linux の両方を保つ最小単位にしてください。

## 開発時の確認

Windows では、使い捨ての `CODEX_HOME` を指定して次を実行します。

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1 -CodexHome <temporary-path>
pwsh -File .\scripts\Test-TaskAwareAgent.ps1 -CodexHome <temporary-path> -ConfigOnlyRuntime
```

Linux では次を実行します。

```bash
./scripts/install-task-aware-agent.sh --codex-home <temporary-path>
./scripts/test-task-aware-agent.sh --codex-home <temporary-path> --config-only-runtime
```

pull request の前に、PowerShell/Bash の構文確認と `git diff --check` も通してください。
実際の model、reasoning effort、sandbox の割り当てを変更する場合は、新しい Codex task から custom agent を起動した live probe も記録してください。

## 変更時の注意

- `.codex/`、認証情報、実ユーザーの `config.toml`、backup を commit しないでください。
- installer は既存設定を保ち、変更前に backup を作る contract を維持してください。
- Windows と Linux の挙動を揃え、片方だけの変更を避けてください。
- security issue は公開 issue ではなく、GitHub Security advisory から報告してください。

明示的に別条件を示さない contribution は、プロジェクトと同じ Apache License 2.0 で提供されます。
