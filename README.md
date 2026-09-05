# Codex Task-Aware Agent

[![CI](https://github.com/Eonshore/Codex-Task-Aware-Agent/actions/workflows/ci.yml/badge.svg)](https://github.com/Eonshore/Codex-Task-Aware-Agent/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Codex の親エージェントがタスクを難易度別に分類し、必要な場合だけ役割別のカスタムエージェントへ委譲するための設定一式です。
OpenAI の公式製品ではなく、Codex の公開仕様に基づくコミュニティプロジェクトです。

この構成では、親に **GPT-6 Astra** を使い、難易度の判定、タスクの分割、子の選択、結果の統合を担当させます。
親を切り替える導入オプションは `gpt-6-astra` と `xhigh` を設定します。
子もすべて Astra とし、D1 は Low・Medium・High、D2 は Medium/High、D3 は High/xhigh、D4 は xhigh/Max を使います。

子のモデルと推論労力を役割ごとに指定することで、親の設定をすべての子が継承することを避けます。
ただし、子もそれぞれトークンと調整時間を使うため、分割する利点がある作業だけを委譲します。
単純な D0 は親が処理し、同時に開く子は最大3つとします。

リポジトリを取得しただけでは Codex の動作は変わりません。
導入スクリプトを実行し、新しいタスクで設定を読み込む必要があります。

## 想定する実行構成

親の基準は Astra xhigh です。既に選択している親のモデルと推論労力は、標準導入では変更しません。
Ultra を利用できる環境では、並列に分割できる大きな作業に Astra Ultra を選べます。
このポリシーは Ultra の有無にかかわらず、委譲の条件を満たす作業を親へ明示します。

| 難易度 | 対象 | 実行役 | モデルと推論労力 | sandbox |
| --- | --- | --- | --- | --- |
| D0 | 単純で明確な1工程 | 親が直接処理 | Astra xhigh（必要に応じて変更） | 親の設定 |
| D1 標準 Low | 少量・同形式で、固定入力と客観的完了条件がある読み取り専用作業 | `luna_task` | Astra Low | read-only |
| D1 標準 Medium | 複数ファイルや異なる形式を扱い、客観的な条件に沿った軽い突き合わせが必要な作業 | `luna_task_medium` | Astra Medium | read-only |
| D1 上位枠 | D1 のまま、異種入力、密な突合、網羅性の確認、多数の境界条件がある作業 | `luna_task_max` | Astra High | read-only |
| D2 標準 | 状態変更を伴う実装、ツールを使う複数工程、通常判断が必要な調査・検証 | `terra_worker` | Astra Medium | 親から継承 |
| D2 上位枠 | D2 のまま、制約の結合、長い検証経路、難しいデバッグ、手戻りコストが大きい作業 | `terra_worker_max` | Astra High | 親から継承 |
| D3 標準 | 一つの難しい判断、曖昧性、高リスク、複数領域、設計判断 | `sol_specialist` | Astra High | read-only |
| D3 上位枠 | 不確実性と結果の重大性がともに高く、証拠の競合、不可逆な設計、セキュリティ上の重大性などを含む作業 | `sol_specialist_max` | Astra xhigh | read-only |
| D4 標準 | 2件以上の独立した D3 作業の所見を、制約や依存関係を踏まえて全体の判断へまとめる作業 | `astra_architect` | Astra xhigh | read-only |
| D4 上位枠 | D3 作業間で証拠や推奨が競合し、全体の判断が不可逆な選択や重大な影響を伴う作業 | `astra_architect_max` | Astra Max | read-only |

能力クラスを D1/D2/D3/D4 から先に決め、その後で必要な推論労力を選びます。
上位枠を選んでも権限や能力境界は広がりません。
D1・D3・D4 の子は読み取り専用です。書き込みを伴う通常実装は、親の権限を継承する D2 の子か親が担当します。
子には再委譲させず、最終統合は親が担当します。

既存六つの役割名とファイル名は互換性のため維持し、D1 Medium を1役、D4 を2役追加して計九役にしています。
モデルは九役とも `gpt-6-astra` です。
`_max` は上位枠の互換名です。D1・D2 の `_max` は High、D3 の `_max` は xhigh、D4 の `_max` は Max に対応します。
役割名からモデルや effort を推測せず、上の表と TOML の設定値を確認してください。

この割り当ては、役割と権限の境界を保ちながら、すべての子を Astra に統一するためのプロジェクトの選択です。
Low・Medium・High・xhigh・Max の品質や消費量を比較したベンチマーク結果ではありません。
モデルの用途と利用可能な設定は [Codex のモデル案内](https://learn.chatgpt.com/docs/models) を参照してください。

D1 の標準枠では、少量・同形式の入力なら Low、複数ファイルや異なる形式を軽く突き合わせるなら Medium を選びます。
網羅性の確認や密な突き合わせ、多数の例外処理が必要なら High を使います。
上位の条件が明らかな場合は、Low や Medium で失敗するのを待たず、適切な役割へ直接渡します。
いずれも客観的な完了条件を持つ読み取り専用作業に限り、実装や設計上の判断は D2 以上へ分けます。

D4 では、親が独立した D3 作業を分割し、その所見が揃ってから、必要に応じて D4 の子へ全体の判断を依頼します。
子へ渡す資料には、少なくとも2件の独立した D3 所見と、その根拠を含めます。
D4 の子は所見の統合を担当し、再委譲や状態変更は行いません。最終判断と実行は親が担当します。
D4 も同時に開く最大3子に数えるため、入力が揃い、空き枠ができてから起動します。

## ルーティングの仕組み

このリポジトリは、`AGENTS.md` に自然言語のルーティング規則を追加します。
独立した分類器や、D0 から D4 までの判定を機械的に強制するディスパッチャーは導入しません。

親は、次の条件をすべて満たす作業だけを委譲します。

1. 親と独立して進められる。
2. 他の作業と区別できる成果または証拠を返せる。
3. 親のコンテキスト消費か経過時間を減らせる見込みがある。
4. 委譲の調整コストが、親による直接処理より小さい。

条件を満たした後、親は能力クラスを選び、そのクラス内で必要十分な推論労力を選びます。
標準 effort を基本とし、追加の時間とトークンを使っても、網羅性の向上や手戻りの回避が見込める場合に上位枠を選びます。
D1 Medium の task packet には、Low では不足する突き合わせの内容を記載します。
上位枠を選ぶ場合は、各クラスの標準 effort では不足する具体的な理由も含めます。
原子的な D0 を、推論労力を下げるためだけに分割しません。
同じ入力と完了条件を共有する小さな作業は、分離によって待ち時間、コンテキスト分離、証拠の独立性が改善しない限り、一つの task packet にまとめます。

子は別の子を起動しません。
`max_concurrent_threads_per_session = 3` とポリシー上の上限により、親から同時に開く子スレッドは最大3つです。
同じファイルや状態を更新するエージェントは1つに限定します。

子からの再委譲は、agent TOML と `AGENTS.md` の指示で禁止します。
旧 `agents.max_depth` は Codex V2 で無視されるため、実効的な強制境界としては使用しません。

`NEEDS_ESCALATION` は Codex ランタイムの自動判定ではなく、子が能力不足の根拠を親へ返すための応答規約です。
合理的に選んだ下位役割が返した場合だけ、親はその根拠を確認し、必要な上位役割へ再委譲します。
最初から D2 または D3 と明らかな作業を、昇格結果を得るためだけに D1 の役割へ渡しません。

子を起動するときは、`spawn_agent` の `agent_type` に `luna_task`、`luna_task_medium`、`luna_task_max`、`terra_worker`、`terra_worker_max`、`sol_specialist`、`sol_specialist_max`、`astra_architect`、`astra_architect_max` のいずれかを明示します。
`task_name` は子タスクの表示名とパスを付ける項目であり、custom agent の選択には使いません。
`task_name = "luna_task"` だけを指定すると、子が親のモデルと推論労力を継承するため、想定したコスト制御になりません。
D1 から D4 までの委譲では、標準と上位枠のどちらでも `agent_type` を必須とし、まず必ず引数付きで起動します。
tool が `agent_type` または custom agent を明示的に拒否した場合だけ、既定の子を起動せず、親で処理して不一致を報告します。
各 spawn は `fork_turns = "none"` を指定し、親の全会話履歴ではなく task packet だけを子へ渡します。
task packet 自体にも再委譲禁止を明記します。

Astra 向けの実行規則として、承認済みの作業を実装と必要な検証まで進めることも明記します。
通常の可逆的な選択は会話の文脈から判断し、結果や権限に影響する不足情報がある場合に質問します。
回答待ちの間も独立した作業は進めます。検証は変更範囲に合わせ、必要な確認が通った後は、追加変更や未解決の問題がある場合に再実行します。
この調整は [Astra の公式ガイド](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra) を参考にし、このリポジトリの最大3子・一段階委譲へ限定しています。

## 前提条件

- Windows では PowerShell 7 以降を使用できること。
- Linux では Bash、`awk`、`grep` を使用できること。
- カスタムエージェントと subagent workflow に対応した現行 Codex を使用していること。
- CI の設定互換性検証基準は Codex CLI 0.149.1。Astra の利用には、アカウントとクライアントのモデル選択欄で対応を確認すること。
- 使用するアカウントで `gpt-6-astra` を利用できること。
- Astra Ultra を使う場合は、対応するアカウントとクライアントで Ultra が有効であること。
- コマンドをこのリポジトリのルートで実行すること。

導入前に、Codex の起動と設定読込が正常であることを確認してください。

```shell
codex --version
codex doctor --summary --no-color --ascii
```

モデルと推論の選択欄では、Astra と各役割に必要な Low・Medium・High・xhigh・Max が表示されることも確認します。
2026-09-05 のローカルモデルカタログ（client version 0.153.0）では、Astra の `low`、`medium`、`high`、`xhigh`、`max`、`ultra` を確認しました。
設定の厳密な読込は、別途 Codex CLI 0.149.1 で検証しました。
カタログへの掲載や設定の読込成功だけでは、実際のモデル呼び出し成功は保証されません。

## 導入で変更するもの

導入スクリプトは、指定した `$CODEX_HOME` を次のように更新します。
`CODEX_HOME` が未設定の場合は `~/.codex` を使用します。

| 対象 | 変更内容 |
| --- | --- |
| `config.toml` | `[agents] enabled = true`、`max_concurrent_threads_per_session = 3` を設定し、旧 key を除去 |
| `AGENTS.md` | マーカーで囲んだ task-aware delegation policy を追加または更新 |
| `agents/luna-task.toml` | Astra Low の読み取り専用エージェントを配置 |
| `agents/luna-task-medium.toml` | Astra Medium の読み取り専用エージェントを配置 |
| `agents/luna-task-max.toml` | Astra High の読み取り専用エージェントを配置 |
| `agents/terra-worker.toml` | Astra Medium の作業エージェントを配置 |
| `agents/terra-worker-max.toml` | Astra High の作業エージェントを配置 |
| `agents/sol-specialist.toml` | Astra High の読み取り専用エージェントを配置 |
| `agents/sol-specialist-max.toml` | Astra xhigh の読み取り専用エージェントを配置（役割名は互換性維持） |
| `agents/astra-architect.toml` | Astra xhigh の読み取り専用D4エージェントを配置 |
| `agents/astra-architect-max.toml` | Astra Max の読み取り専用D4エージェントを配置 |

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

親の既定値を Astra xhigh にする場合は、`-SetAstraDefault` を指定します。

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1 -SetAstraDefault
```

フルアクセスも設定する場合は、`-EnableFullAccess` を追加します。

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1 -SetAstraDefault -EnableFullAccess
```

別の Codex 環境へ試験導入する場合は `-CodexHome <path>`、変更予定だけを確認する場合は `-WhatIf` を指定できます。

PowerShell 版も、`config.toml` がない空の `CODEX_HOME` を初期化できます。

### Linux

標準構成を導入します。

```bash
./scripts/install-task-aware-agent.sh
```

親の既定値を Astra xhigh にする場合は、`--set-astra-default` を指定します。

```bash
./scripts/install-task-aware-agent.sh --set-astra-default
```

フルアクセスも設定する場合は、`--enable-full-access` を追加します。

```bash
./scripts/install-task-aware-agent.sh --set-astra-default --enable-full-access
```

別の Codex 環境へ導入する場合は、`CODEX_HOME` 環境変数または `--codex-home <path>` を指定できます。
Linux 版は、空の `CODEX_HOME` に必要なファイルを新規作成できます。
Windows 側の checkout を WSL から使う場合は、`.sh` の改行が LF であることを確認してください。
CRLF のまま実行すると、shebang の `bash` を解決できず起動に失敗します。

### 親の effort と旧オプション

`-SetAstraDefault` と `--set-astra-default` は `gpt-6-astra` と `xhigh` を設定します。
既に親へ Ultra などを選択していて、その effort を保つ場合は標準導入を使ってください。
Ultra を新たに使う場合は、対応クライアントのモデル選択で Astra と Ultra を選びます。

旧 `-SetSolDefault` と `--set-sol-default` は廃止しました。
指定すると、ファイルを変更する前に Astra オプションへの移行案内を表示して停止します。
親も Astra に切り替える場合は `-SetAstraDefault` または `--set-astra-default` を使ってください。

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

どちらの検証スクリプトも、配置したファイル、主要な設定値、九つの子のモデル ID、推論労力、宣言した sandbox を静的に確認します。
`codex` コマンドが見つかる場合は、続けて `codex doctor` を実行します。

この検証は、runtime が子へ適用した実効 sandbox、モデルの利用権限、実際の子の起動、D0 から D4 までの分類結果までは確認しません。
導入後は Codex を再起動するか、新しいタスクを開始し、次の手順で実動作も確認してください。

1. 親のモデルが Astra、effort が選択した値（導入オプションなら xhigh）になっていることを確認する。
2. 一つのファイルから既知の文字列を読むだけの D0 を依頼し、子を起動しないことを確認する。
3. 少量・同形式の固定入力を持つ読み取り専用 D1 を依頼し、`luna_task` が Low で動くことを確認する。
4. 複数ファイルや異なる形式の軽い突き合わせを行う D1 を依頼し、`luna_task_medium` が Medium で動くことを確認する。
5. 密な突き合わせや網羅性の確認が必要な D1 を依頼し、`luna_task_max` が High で動くことを確認する。
6. 専用の空ディレクトリに一つのファイルを作成して検証する D2 を依頼し、`terra_worker` を確認する。
7. 複数ファイルの結合制約と長い検証経路を持つ D2 を依頼し、`terra_worker_max` を確認する。
8. 一つの明確な設計トレードオフを判断する D3 を依頼し、`sol_specialist` が High で動くことを確認する。
9. 証拠の競合と判断の重大性がともに高い D3 を依頼し、`sol_specialist_max` が xhigh で動くことを確認する。
10. 2件以上の独立した D3 所見をまとめる D4 を依頼し、`astra_architect` が xhigh で動くことを確認する。
11. D3 所見間で重大な推奨や証拠が競合する D4 を依頼し、`astra_architect_max` が Max で動くことを確認する。
12. 親が D0 では spawn せず、D1 から D4 では対応する `agent_type` を渡すこと、子が再委譲せず最大3子を守ることを確認する。
13. 各子の詳細で、model がすべて `gpt-6-astra`、effort が上の表と一致することを確認する。

`AGENTS.md` の指示チェーンは新しい実行の開始時に構築されるため、導入前から開いているタスクでは確認できません。

## 復元

自動アンインストール用のスクリプトはありません。
導入前の状態へ戻す場合は、`$CODEX_HOME/task-aware-backups/<timestamp>/` に保存されたファイルを元の場所へ戻します。

再導入している場合、最新のバックアップが初回導入前の状態とは限りません。
戻したい導入時に表示された `Backup:` のパスを選び、初回導入前へ戻す場合は初回のバックアップを使ってください。
導入後に `config.toml` や `AGENTS.md` を変更している場合は、バックアップをそのまま上書きせず、差分を確認して task-aware 関連の設定だけを手動で統合してください。

導入前に存在しなかったファイルはバックアップへ含まれません。
その場合は、追加された九つのエージェントファイルと、`AGENTS.md` の `BEGIN CODEX TASK-AWARE AGENT` から `END CODEX TASK-AWARE AGENT` までのブロックを手動で取り除く必要があります。

## ファイル構成

- `config/AGENTS.task-aware.md`：グローバル指示へ追加するルーティング規則
- `config/config.task-aware.toml`：`config.toml` へ統合する設定例
- `agents/*.toml`：Astra の役割別エージェント（旧役割名を維持）
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
- 上位枠は必要な能力、書き込み、曖昧さ、リスクを先に判定して選びます。価格だけを理由に選びません。
- High や Max は追加の推論時間とトークンを使うため、各クラスの標準 effort で十分な作業には使いません。
- Ultra を選んだ場合も、独立した成果があり、調整コストを上回る利点がある作業を委譲します。
- モデルが利用できることと、ルーティングが適切であることは静的テストだけでは保証できません。
- ルーティングは親の判断に依存するため、D0 から D4 までの境界は決定的ではありません。
- Codex Desktop や CLI の実効 permission profile が親の権限を子へ強制する runtime では、role TOML の `sandbox_mode` より親の実効権限が優先される場合があります。D1・D3・D4 の developer instructions も書き込みを禁止しますが、これは OS sandbox と同じ強制境界ではありません。

## 参考資料

- [Models](https://learn.chatgpt.com/docs/models)
- [GPT-6 Astra guide](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra)
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Configuration Reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Configuration Schema](https://developers.openai.com/codex/config-schema.json)
- [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex changelog](https://learn.chatgpt.com/docs/changelog)
