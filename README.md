# Codex Task-Aware Agent

Codex の親エージェントがタスクを難易度別に分類し、必要な場合だけ役割別のカスタムエージェントへ委譲するための設定一式です。

この構成が想定する親は、`gpt-5.6-sol` を推論労力 `ultra` で動かす **Sol Ultra** です。
親は難易度判定、タスクの分割、子の選択、結果の統合を担当し、子には Luna Low、Terra Medium、Sol High を使い分けます。

これにより、すべての子が親の高い推論労力を継承して消費量が膨らむことを避けつつ、メインスレッドへ途中経過が流れ込む量を抑えます。

リポジトリを取得しただけでは Codex の動作は変わりません。
導入スクリプトを実行し、新しいタスクで設定を読み込む必要があります。

## 想定する実行構成

Sol はモデル、Ultra は推論労力と委譲を含む実行設定です。
Ultra は別のモデル名ではありません。

対応するアカウントとクライアントで Sol Ultra を選ぶと、親は最大の推論労力を使い、分割可能な作業をサブエージェントへ能動的に委譲します。
このリポジトリは、その委譲に D0 から D4 までの判断基準と、用途別に固定した三つの子エージェントを追加します。

| 難易度 | 対象 | 実行役 | モデルと推論労力 | sandbox |
| --- | --- | --- | --- | --- |
| D0 | 単純で明確な1工程 | 親が直接処理 | Sol Ultra | 親の設定 |
| D1 | 抽出、分類、変換、反復チェック | `luna_task` | Luna Low | read-only |
| D2 | 境界が明確な調査、通常実装、検証 | `terra_worker` | Terra Medium | 親から継承 |
| D3 | 曖昧、高リスク、複数領域、設計判断 | `sol_specialist` | Sol High | read-only |
| D4 | 独立した D3 タスクが複数 | 親が分割して統合 | Sol Ultra | 親と選択した子の設定 |

`sol_specialist` は難しい判断と検証計画を返す読み取り専用の役割です。
書き込みを伴う通常実装は、親の権限を継承する `terra_worker` か親が担当します。
Ultra を使うのは親だけで、D3 の `sol_specialist` も Sol High に抑えています。
複数の判断をまたぐ推論と最終統合を親へ残し、子ごとに Ultra の推論コストが発生することを避けるためです。

## ルーティングの仕組み

このリポジトリは、`AGENTS.md` に自然言語のルーティング規則を追加します。
独立した分類器や、D0 から D4 までの判定を機械的に強制するディスパッチャーは導入しません。

親は、次の条件をすべて満たす作業だけを委譲します。

1. 親と独立して進められる。
2. 他の作業と区別できる成果または証拠を返せる。
3. 親のコンテキスト消費か経過時間を減らせる見込みがある。
4. 委譲の調整コストが、親による直接処理より小さい。

子は別の子を起動しません。
`max_threads = 4` とポリシー上の上限により、親から同時に使う子は最大3つです。
同じファイルや状態を更新するエージェントは1つに限定します。

`NEEDS_ESCALATION` は Codex ランタイムの自動判定ではなく、子が能力不足の根拠を親へ返すための応答規約です。
親はその根拠を確認してから、必要な場合だけ上位の役割へ再委譲します。

## 前提条件

- Windows では PowerShell 7 以降を使用できること。
- Linux では Bash、`awk`、`grep` を使用できること。
- カスタムエージェントと multi-agent に対応した Codex を使用していること。
- 使用するアカウントで `gpt-5.6-luna`、`gpt-5.6-terra`、`gpt-5.6-sol` を利用できること。
- Sol Ultra を使う場合は、対応するアカウントとクライアントで Ultra が有効であること。
- コマンドをこのリポジトリのルートで実行すること。

導入前に、Codex の起動と設定読込が正常であることを確認してください。

```shell
codex --version
codex doctor --summary --no-color --ascii
```

モデルと推論の選択欄では、三つの子モデルと、親に使う Sol Ultra が表示されることも確認します。

Ultra を利用できない環境でも、Sol xhigh を親にして同じ D0 から D4 までのルーティング規則を使えます。
ただし、それはこのリポジトリが想定する Sol Ultra と同じ実行構成ではありません。

## 導入で変更するもの

導入スクリプトは、指定した `$CODEX_HOME` を次のように更新します。
`CODEX_HOME` が未設定の場合は `~/.codex` を使用します。

| 対象 | 変更内容 |
| --- | --- |
| `config.toml` | `[features] multi_agent = true`、`[agents] max_threads = 4`、`max_depth = 1` を設定 |
| `AGENTS.md` | マーカーで囲んだ task-aware delegation policy を追加または更新 |
| `agents/luna-task.toml` | Luna Low の読み取り専用エージェントを配置 |
| `agents/terra-worker.toml` | Terra Medium の作業エージェントを配置 |
| `agents/sol-specialist.toml` | Sol High の読み取り専用エージェントを配置 |

既存ファイルは、変更前に `$CODEX_HOME/task-aware-backups/<timestamp>/` へ退避します。
同名のカスタムエージェントファイルは上書きされます。
この設定は `$CODEX_HOME` を共有する新しい Codex タスクへ適用されるため、特定のプロジェクトだけに限定されません。

## 導入

標準導入は、既存の親モデル、親の推論労力、承認ポリシー、sandbox を変更しません。

### Windows

標準構成を導入します。

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1
```

親の既定値を Sol xhigh にする場合は、`-SetSolDefault` を指定します。

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1 -SetSolDefault
```

フルアクセスも設定する場合は、`-EnableFullAccess` を追加します。

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1 -SetSolDefault -EnableFullAccess
```

別の Codex 環境へ試験導入する場合は `-CodexHome <path>`、変更予定だけを確認する場合は `-WhatIf` を指定できます。

PowerShell 版は、まだ `config.toml` がない空の `CODEX_HOME` を初期化できません。
Codex で設定を一度保存するか、有効な TOML を含む `config.toml` を作成してから導入してください。

### Linux

標準構成を導入します。

```bash
./scripts/install-task-aware-agent.sh
```

親の既定値を Sol xhigh にする場合は、`--set-sol-default` を指定します。

```bash
./scripts/install-task-aware-agent.sh --set-sol-default
```

フルアクセスも設定する場合は、`--enable-full-access` を追加します。

```bash
./scripts/install-task-aware-agent.sh --set-sol-default --enable-full-access
```

別の Codex 環境へ導入する場合は、`CODEX_HOME` 環境変数または `--codex-home <path>` を指定できます。
Linux 版は、空の `CODEX_HOME` に必要なファイルを新規作成できます。
Windows 側の checkout を WSL から使う場合は、`.sh` の改行が LF であることを確認してください。
CRLF のまま実行すると、shebang の `bash` を解決できず起動に失敗します。

### Sol Ultra の選択

`-SetSolDefault` と `--set-sol-default` が設定する親の既定値は、`gpt-5.6-sol` と `xhigh` です。
どちらのオプションだけでも Sol Ultra にはなりません。

想定構成どおりに使う場合は、導入後に対応クライアントのモデルと推論の選択欄で Sol と Ultra を選んでください。
現在の Codex が `ultra` を設定値として受理する場合は、`config.toml` で次のように指定することもできます。

```toml
model = "gpt-5.6-sol"
model_reasoning_effort = "ultra"
```

インストーラーが `xhigh` を使うのは、Ultra を設定ファイルから選べないクライアントとの互換性を残すためです。

### フルアクセスの影響

`-EnableFullAccess` と `--enable-full-access` は、`approval_policy = "never"` と `sandbox_mode = "danger-full-access"` をグローバル設定へ書き込みます。
この指定は、親だけでなく sandbox を親から継承する `terra_worker` にも影響します。
同じ `$CODEX_HOME` を使うほかのプロジェクトにも適用されるため、信頼できる環境でのみ使用してください。

既存の `config.toml` に `default_permissions` がある場合は、`-EnableFullAccess` または `--enable-full-access` をそのまま使わないでください。
Codex は `default_permissions` と `sandbox_mode` の併用を想定しておらず、インストーラーも競合を検出または解消しません。
どちらの権限方式を使うかを決め、既存設定を整理してから導入してください。

## 検証

### Windows

```powershell
pwsh -File .\scripts\Test-TaskAwareAgent.ps1
```

ランタイム確認を省く場合は `-SkipRuntime`、静的検査の対象を変える場合は `-CodexHome <path>` を指定できます。
PowerShell 版の `codex doctor` は、`-CodexHome` の値ではなく、実行プロセスが使用している Codex 設定を検査します。

### Linux

```bash
./scripts/test-task-aware-agent.sh
```

ランタイム確認を省く場合は `--skip-runtime`、対象を変える場合は `--codex-home <path>` を指定できます。
Linux 版は対象の `CODEX_HOME` を明示し、`codex --strict-config doctor --summary` を実行します。

どちらの検証スクリプトも、配置したファイル、主要な設定値、三つの子のモデル ID を静的に確認します。
`codex` コマンドが見つかる場合は、続けて `codex doctor` を実行します。

この検証は、子の推論労力と sandbox、モデルの利用権限、実際の子の起動、D0 から D4 までの分類結果までは確認しません。
導入後は Codex を再起動するか、新しいタスクを開始し、次の手順で実動作も確認してください。

1. 親のモデルと推論の選択欄が Sol Ultra になっていることを確認する。
2. 「`agents/*.toml` から name と model を抽出して表にする」のような、完了条件が明確な D1 タスクを依頼する。
3. 親が D1 と `luna_task` を報告し、子のタスクが起動することを確認する。
4. 子の詳細を開き、役割と使用モデルが想定どおりであることを確認する。

`AGENTS.md` の指示チェーンは新しい実行の開始時に構築されるため、導入前から開いているタスクでは確認できません。

## 復元

自動アンインストール用のスクリプトはありません。
導入前の状態へ戻す場合は、`$CODEX_HOME/task-aware-backups/<timestamp>/` に保存されたファイルを元の場所へ戻します。

再導入している場合、最新のバックアップが初回導入前の状態とは限りません。
戻したい導入時に表示された `Backup:` のパスを選び、初回導入前へ戻す場合は初回のバックアップを使ってください。
導入後に `config.toml` や `AGENTS.md` を変更している場合は、バックアップをそのまま上書きせず、差分を確認して task-aware 関連の設定だけを手動で統合してください。

導入前に存在しなかったファイルはバックアップへ含まれません。
その場合は、追加された三つのエージェントファイルと、`AGENTS.md` の `BEGIN CODEX TASK-AWARE AGENT` から `END CODEX TASK-AWARE AGENT` までのブロックを手動で取り除く必要があります。

## ファイル構成

- `config/AGENTS.task-aware.md`：グローバル指示へ追加するルーティング規則
- `config/config.task-aware.toml`：`config.toml` へ統合する設定例
- `agents/*.toml`：Luna、Terra、Sol の役割別エージェント
- `scripts/Install-TaskAwareAgent.ps1`：バックアップ付き導入スクリプト
- `scripts/Test-TaskAwareAgent.ps1`：配置と Codex 設定の検証スクリプト
- `scripts/install-task-aware-agent.sh`：Linux 向けのバックアップ付き導入スクリプト
- `scripts/test-task-aware-agent.sh`：Linux 向けの配置と Codex 設定の検証スクリプト

## 設計上の注意

- サブエージェントはメインスレッドのノイズを減らしますが、総トークン量や待ち時間が必ず減るわけではありません。
- Ultra 自体も分割可能な作業へサブエージェントを使うため、独立した成果がある作業だけに委譲を絞ります。
- モデルが利用できることと、ルーティングが適切であることは静的テストだけでは保証できません。
- ルーティングは親の判断に依存するため、D0 から D4 までの境界は決定的ではありません。

## 参考資料

- [Models](https://learn.chatgpt.com/docs/models)
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Configuration Reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
