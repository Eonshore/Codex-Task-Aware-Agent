# Codex Task-Aware Agent

[![CI](https://github.com/Eonshore/Codex-Task-Aware-Agent/actions/workflows/ci.yml/badge.svg)](https://github.com/Eonshore/Codex-Task-Aware-Agent/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Codex の親エージェントがタスクを難易度別に分類し、必要な場合だけ役割別のカスタムエージェントへ委譲するための設定一式です。
OpenAI の公式製品ではなく、Codex の公開仕様に基づくコミュニティプロジェクトです。

この構成が想定する親は、`gpt-5.6-sol` をクライアントの Ultra モードで動かす **Sol Ultra** です。
親は難易度判定、タスクの分割、子の選択、結果の統合を担当します。
子には Luna Low/Max、Terra Medium/Max、Sol High/Max を使い分けます。

これにより、すべての子が親の高い推論労力を継承して消費量が膨らむことを避けつつ、メインスレッドへ途中経過が流れ込む量を抑えます。
現行の価格差は、固定契約の読み取り専用作業を Luna へ寄せ、各難度内で必要な場合に高い推論労力を選ぶ根拠にします。
安価であることだけを理由に子を細分化はしません。
各 subagent は独自に token と調整時間を使うため、D0 の直接処理と最大3子の上限は維持します。

リポジトリを取得しただけでは Codex の動作は変わりません。
導入スクリプトを実行し、新しいタスクで設定を読み込む必要があります。

## 想定する実行構成

Sol はモデル、Ultra は対応するモデルと環境で最大推論と能動的な委譲を利用する実行モードです。
現行 Codex は、対応モデルの `model_reasoning_effort = "ultra"` も受け付けます。
このリポジトリでは、親の統合と委譲に Ultra を残し、子の上限を Max にします。

対応するアカウントとクライアントで Sol Ultra を選ぶと、親は分割可能な作業をサブエージェントへ能動的に委譲します。
このリポジトリは、その委譲に D0 から D4 までの能力分類と、同じ難度内で推論労力を選ぶ六つの子エージェントを追加します。

| 難易度 | 対象 | 実行役 | モデルと推論労力 | sandbox |
| --- | --- | --- | --- | --- |
| D0 | 単純で明確な1工程 | 親が直接処理 | Sol Ultra | 親の設定 |
| D1 標準 | 小さく均質で、固定入力と客観的完了条件がある読み取り専用作業 | `luna_task` | Luna Low | read-only |
| D1 Max枠 | D1 のまま、異種入力、密な突合、coverage 重視、多数の edge case がある作業 | `luna_task_max` | Luna Max | read-only |
| D2 標準 | 状態変更を伴う実装、tool-heavy な複数工程、通常判断が必要な調査・検証 | `terra_worker` | Terra Medium | 親から継承 |
| D2 Max枠 | D2 のまま、制約の結合、長い検証経路、難しいデバッグ、手戻りコストが大きい作業 | `terra_worker_max` | Terra Max | 親から継承 |
| D3 標準 | 一つの難しい判断、曖昧性、高リスク、複数領域、設計判断 | `sol_specialist` | Sol High | read-only |
| D3 Max枠 | 不確実性と結果の重大性がともに高く、証拠競合、不可逆設計、security、敵対的 edge case を含む作業 | `sol_specialist_max` | Sol Max | read-only |
| D4 | 独立した D3 タスクが複数 | 親が分割して統合 | Sol Ultra | 親と選択した子の設定 |

能力クラスを D1/D2/D3 から先に決め、その後で標準またはMax枠を選びます。
Max枠を選んでも権限や能力境界は広がりません。
Luna の二役と Sol の二役は読み取り専用で、書き込みを伴う通常実装は、親の権限を継承する Terra の二役か親が担当します。
Ultra は親だけに残し、複数の判断をまたぐ推論と最終統合を親が担当します。
上位枠は三モデルとも Max に統一します。
`xhigh` は標準とMaxの間に独立した能力境界を作らないため、別roleにはしません。

## ルーティングの仕組み

このリポジトリは、`AGENTS.md` に自然言語のルーティング規則を追加します。
独立した分類器や、D0 から D4 までの判定を機械的に強制するディスパッチャーは導入しません。

親は、次の条件をすべて満たす作業だけを委譲します。

1. 親と独立して進められる。
2. 他の作業と区別できる成果または証拠を返せる。
3. 親のコンテキスト消費か経過時間を減らせる見込みがある。
4. 委譲の調整コストが、親による直接処理より小さい。

条件を満たした後、親は能力クラスを選び、そのクラス内で必要十分な推論労力を選びます。
標準 effort が基本ですが、完全性の向上または手戻りの回避が見込める場合は、価格低下を踏まえてMax枠を積極的に選べます。
Max枠の task packet には、標準 effort では誤りや手戻りが増える具体的な理由を含めます。
原子的な D0 を Luna が安価であるという理由だけで分割しません。
同じ入力と完了条件を共有する小さな作業は、分離によって待ち時間、コンテキスト分離、証拠の独立性が改善しない限り、一つの task packet にまとめます。

子は別の子を起動しません。
`max_concurrent_threads_per_session = 3` とポリシー上の上限により、親から同時に開く子スレッドは最大3つです。
同じファイルや状態を更新するエージェントは1つに限定します。

子からの再委譲は、agent TOML と `AGENTS.md` の指示で禁止します。
旧 `agents.max_depth` は Codex V2 で無視されるため、実効的な強制境界としては使用しません。

`NEEDS_ESCALATION` は Codex ランタイムの自動判定ではなく、子が能力不足の根拠を親へ返すための応答規約です。
合理的に選んだ下位役割が返した場合だけ、親はその根拠を確認し、必要な上位役割へ再委譲します。
最初から D2 または D3 と明らかな作業を、昇格結果を得るためだけに Luna へ渡しません。

子を起動するときは、`spawn_agent` の `agent_type` に `luna_task`、`luna_task_max`、`terra_worker`、`terra_worker_max`、`sol_specialist`、`sol_specialist_max` のいずれかを明示します。
`task_name` は子タスクの表示名とパスを付ける項目であり、custom agent の選択には使いません。
`task_name = "luna_task"` だけを指定すると、子が親のモデルと推論労力を継承するため、想定したコスト制御になりません。
D1 から D3 までの委譲では、標準とMax枠のどちらでも `agent_type` を必須とし、まず必ず引数付きで起動します。
tool が `agent_type` または custom agent を明示的に拒否した場合だけ、既定の子を起動せず、親で処理して不一致を報告します。
各 spawn は `fork_turns = "none"` を指定し、親の全会話履歴ではなく task packet だけを子へ渡します。
task packet 自体にも再委譲禁止を明記します。

## 前提条件

- Windows では PowerShell 7 以降を使用できること。
- Linux では Bash、`awk`、`grep` を使用できること。
- カスタムエージェントと subagent workflow に対応した現行 Codex を使用していること。
- この公開候補の検証基準である Codex CLI 0.145.0 以降を使用すること。
- 使用するアカウントで `gpt-5.6-luna`、`gpt-5.6-terra`、`gpt-5.6-sol` を利用できること。
- Sol Ultra を使う場合は、対応するアカウントとクライアントで Ultra が有効であること。
- コマンドをこのリポジトリのルートで実行すること。

導入前に、Codex の起動と設定読込が正常であることを確認してください。

```shell
codex --version
codex doctor --summary --no-color --ascii
```

モデルと推論の選択欄では、三つの子モデル、High/Max を含む必要な effort、親に使う Sol Ultra が表示されることも確認します。

Ultra を利用できない環境でも、Sol xhigh を親にして同じ D0 から D4 までのルーティング規則を使えます。
ただし、それはこのリポジトリが想定する Sol Ultra と同じ実行構成ではありません。

## 導入で変更するもの

導入スクリプトは、指定した `$CODEX_HOME` を次のように更新します。
`CODEX_HOME` が未設定の場合は `~/.codex` を使用します。

| 対象 | 変更内容 |
| --- | --- |
| `config.toml` | `[agents] enabled = true`、`max_concurrent_threads_per_session = 3` を設定し、旧 key を除去 |
| `AGENTS.md` | マーカーで囲んだ task-aware delegation policy を追加または更新 |
| `agents/luna-task.toml` | Luna Low の読み取り専用エージェントを配置 |
| `agents/luna-task-max.toml` | Luna Max の読み取り専用エージェントを配置 |
| `agents/terra-worker.toml` | Terra Medium の作業エージェントを配置 |
| `agents/terra-worker-max.toml` | Terra Max の作業エージェントを配置 |
| `agents/sol-specialist.toml` | Sol High の読み取り専用エージェントを配置 |
| `agents/sol-specialist-max.toml` | Sol Max の読み取り専用エージェントを配置 |

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

PowerShell 版も、`config.toml` がない空の `CODEX_HOME` を初期化できます。

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

想定構成どおりに使う場合は、導入後に対応クライアントのモデル選択で Sol と Ultra を選んでください。
インストーラーは、アカウントやクライアントごとの Ultra 対応を暗黙に仮定しないため、`model_reasoning_effort = "ultra"` を自動では書き込みません。
対応を確認できた環境では、クライアントの選択または明示的な設定で親を Ultra にしてください。

### フルアクセスの影響

`-EnableFullAccess` と `--enable-full-access` は、`approval_policy = "never"` と `sandbox_mode = "danger-full-access"` をグローバル設定へ書き込みます。
この指定は、親だけでなく sandbox を親から継承する `terra_worker` と `terra_worker_max` にも影響します。
同じ `$CODEX_HOME` を使うほかのプロジェクトにも適用されるため、信頼できる環境でのみ使用してください。

既存の `config.toml` に `default_permissions` がある場合、インストーラーは `-EnableFullAccess` または `--enable-full-access` をエラーで停止します。
Codex は `default_permissions` と `sandbox_mode` の併用を想定していないため、どちらの権限方式を使うかを決め、既存設定を整理してから再実行してください。

## 検証

### Windows

```powershell
pwsh -File .\scripts\Test-TaskAwareAgent.ps1
```

ランタイム確認を省く場合は `-SkipRuntime`、対象を変える場合は `-CodexHome <path>` を指定できます。
認証情報のない clean home や CI では `-ConfigOnlyRuntime` を加えると、strict config load だけを必須にし、認証や接続など別カテゴリの doctor failure を分離できます。
PowerShell 版も対象の `CODEX_HOME` を明示し、`codex --strict-config doctor --summary` を実行します。

### Linux

```bash
./scripts/test-task-aware-agent.sh
```

ランタイム確認を省く場合は `--skip-runtime`、対象を変える場合は `--codex-home <path>` を指定できます。
認証情報のない clean home や CI では `--config-only-runtime` を加えます。
Linux 版は対象の `CODEX_HOME` を明示し、`codex --strict-config doctor --summary` を実行します。

どちらの検証スクリプトも、配置したファイル、主要な設定値、六つの子のモデル ID、推論労力、宣言した sandbox を静的に確認します。
`codex` コマンドが見つかる場合は、続けて `codex doctor` を実行します。

この検証は、runtime が子へ適用した実効 sandbox、モデルの利用権限、実際の子の起動、D0 から D4 までの分類結果までは確認しません。
導入後は Codex を再起動するか、新しいタスクを開始し、次の手順で実動作も確認してください。

1. 親のモデルと推論の選択欄が Sol Ultra になっていることを確認する。
2. 一つのファイルから既知の文字列を読むだけの D0 を依頼し、子を起動しないことを確認する。
3. 小さく均質で固定契約を持つ読み取り専用 D1 を依頼し、`luna_task` を確認する。
4. 異種入力の密な突合と coverage 判定を伴うが、客観的に完了判定できる D1 を依頼し、`luna_task_max` を確認する。
5. 専用の空ディレクトリに一つのファイルを作成して検証する D2 を依頼し、`terra_worker` を確認する。
6. 複数ファイルの結合制約と長い検証経路を持つ D2 を依頼し、`terra_worker_max` を確認する。
7. 一つの明確な設計トレードオフを判断する D3 を依頼し、`sol_specialist` を確認する。
8. 証拠が競合し、不可逆性または security 上の重大性も高い D3 を依頼し、`sol_specialist_max` を確認する。
9. 親が D0 では spawn せず、D1 から D3 では対応する標準またはMax枠の `agent_type` を渡すことを確認する。
10. 各子の詳細を開き、Luna Low/Max、Terra Medium/Max、Sol High/Max が実際に適用されていることを確認する。

`AGENTS.md` の指示チェーンは新しい実行の開始時に構築されるため、導入前から開いているタスクでは確認できません。

## 復元

自動アンインストール用のスクリプトはありません。
導入前の状態へ戻す場合は、`$CODEX_HOME/task-aware-backups/<timestamp>/` に保存されたファイルを元の場所へ戻します。

再導入している場合、最新のバックアップが初回導入前の状態とは限りません。
戻したい導入時に表示された `Backup:` のパスを選び、初回導入前へ戻す場合は初回のバックアップを使ってください。
導入後に `config.toml` や `AGENTS.md` を変更している場合は、バックアップをそのまま上書きせず、差分を確認して task-aware 関連の設定だけを手動で統合してください。

導入前に存在しなかったファイルはバックアップへ含まれません。
その場合は、追加された六つのエージェントファイルと、`AGENTS.md` の `BEGIN CODEX TASK-AWARE AGENT` から `END CODEX TASK-AWARE AGENT` までのブロックを手動で取り除く必要があります。

## ファイル構成

- `config/AGENTS.task-aware.md`：グローバル指示へ追加するルーティング規則
- `config/config.task-aware.toml`：`config.toml` へ統合する設定例
- `agents/*.toml`：Luna、Terra、Sol の役割別エージェント
- `scripts/Install-TaskAwareAgent.ps1`：バックアップ付き導入スクリプト
- `scripts/Test-TaskAwareAgent.ps1`：配置と Codex 設定の検証スクリプト
- `scripts/install-task-aware-agent.sh`：Linux 向けのバックアップ付き導入スクリプト
- `scripts/test-task-aware-agent.sh`：Linux 向けの配置と Codex 設定の検証スクリプト

## リリース

`v*` tag を push すると、GitHub Actions が Windows/Linux の clean-home round trip を再実行し、次の成果物を GitHub Release に作成します。

- source archive の `.zip`
- source archive の `.tar.gz`
- 両 archive を検証する `SHA256SUMS`

公開前の手順と必須確認は [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)、変更履歴は [CHANGELOG.md](CHANGELOG.md) を参照してください。

## ライセンス

Apache License 2.0 です。SPDX identifier は `Apache-2.0` です。全文は [LICENSE](LICENSE) を参照してください。

## 設計上の注意

- サブエージェントはメインスレッドのノイズを減らしますが、総トークン量や待ち時間が必ず減るわけではありません。
- 価格低下は同じ難度内でMax枠を選ぶ閾値を下げますが、必要な能力、書き込み、曖昧さ、リスクより優先しません。
- Max は応答時間と token 使用量を増やすため、標準 effort で十分な作業には使いません。
- Ultra 自体も分割可能な作業へサブエージェントを使うため、独立した成果がある作業だけに委譲を絞ります。
- モデルが利用できることと、ルーティングが適切であることは静的テストだけでは保証できません。
- ルーティングは親の判断に依存するため、D0 から D4 までの境界は決定的ではありません。
- Codex Desktop や CLI の実効 permission profile が親の権限を子へ強制する runtime では、role TOML の `sandbox_mode` より親の実効権限が優先される場合があります。Luna と Sol の developer instructions も書き込みを禁止しますが、これは OS sandbox と同じ強制境界ではありません。

## 参考資料

- [Models](https://learn.chatgpt.com/docs/models)
- [Codex rate card](https://help.openai.com/en/articles/20001106-codex-rate-card)
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Configuration Reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Configuration Schema](https://developers.openai.com/codex/config-schema.json)
- [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex changelog](https://learn.chatgpt.com/docs/changelog)
