# Codex Task-Aware Agent

[![CI](https://github.com/Eonshore/Codex-Task-Aware-Agent/actions/workflows/ci.yml/badge.svg)](https://github.com/Eonshore/Codex-Task-Aware-Agent/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Codex の親エージェントがタスクを難易度別に分類し、必要な場合だけ役割別のカスタムエージェントへ委譲するための設定一式です。
OpenAI の公式製品ではなく、Codex の公開仕様に基づくコミュニティプロジェクトです。

この配布構成では、親に **Astra（`gpt-6-astra`）** を使えます。
親は難易度判定、タスクの分割、子の選択、結果の統合を担当します。
子には Luna Low/Max、Terra Medium/Max、Sol High/Max と、明示的に許可された管理者操作用の Sol Max を使い分けます。
従来の Sol を親にする構成も引き続き利用できます。

親を Astra にしても、子は各役割のモデルと推論労力を使います。
すべての子が親の設定を継承して消費量が膨らむことを避けつつ、メインスレッドへ途中経過が流れ込む量を抑えるための構成です。
子も個別にトークンと調整時間を使うため、独立した成果を返せる作業だけを委譲します。

リポジトリを取得しただけでは Codex の動作は変わりません。
導入スクリプトを実行し、新しいタスクで設定を読み込む必要があります。

## 想定する実行構成

Astra の導入オプションは、親の既定値を `gpt-6-astra` と `model_reasoning_effort = "xhigh"`（Extra High）に設定します。
標準導入では親の設定を保持するので、すでに選択した Astra の推論労力もそのまま使えます。
子の推論労力は、役割ごとの標準値または Max に固定します。

ローカルの Codex は、利用者からの明示依頼、または適用されるプロジェクト・スキルの指示に基づいて子を起動します。
この配布ポリシーは、後述の委譲条件をすべて満たした場合に限って委譲を求めます。
Astra や Ultra を選ぶこと自体を、子を起動する条件にはしません。詳しくは [公式 Subagents 資料](https://learn.chatgpt.com/docs/agent-configuration/subagents)を参照してください。

| 難易度 | 対象 | 実行役 | モデルと推論労力 | sandbox |
| --- | --- | --- | --- | --- |
| D0 | 単純で明確な1工程 | 親が直接処理 | 選択した親（Astra など） | 親の設定 |
| D1 標準 | 小さく均質で、固定入力と客観的完了条件がある読み取り専用作業 | `luna_task` | Luna Low | read-only |
| D1 Max枠 | D1 のまま、異種入力、密な突合、coverage 重視、多数の edge case がある作業 | `luna_task_max` | Luna Max | read-only |
| D2 標準 | 範囲と完了条件が明確な、状態変更を伴う実装・修復・統合 | `terra_worker` | Terra Medium | workspace-write |
| D2 Max枠 | D2 のまま、制約の結合、長い検証経路、難しいデバッグ、手戻りコストが大きい作業 | `terra_worker_max` | Terra Max | workspace-write |
| D3 標準 | 独立した判断や証拠が必要で、委譲条件を満たす難しい読み取り専用作業 | `sol_specialist` | Sol High | read-only |
| D3 Max枠 | 不確実性と結果の重大性がともに高く、証拠競合、不可逆設計、security、敵対的 edge case を含む作業 | `sol_specialist_max` | Sol Max | read-only |
| D4 | D3 の候補が複数あり、各候補の委譲条件を個別に判定 | 親が分割して統合 | 選択した親（Astra など） | 親と選択した子の設定 |
| 管理者操作 | 操作・対象・昇格方法について利用者の明示許可がある単一作業 | `sol_admin_max` | Sol Max | danger-full-access |

作業を能力クラスに分類し、委譲するかを判定した後で、役割と標準またはMax枠を選びます。
Max枠を選んでも権限や能力境界は広がりません。
単独の D3 は原則として親が担当し、独立した検証や判断に価値があり、すべての委譲条件を満たす場合だけ Sol へ渡します。
読み取り専用の調査を、通常の判断が必要という理由だけで、書き込み役の Terra へ送りません。
表の sandbox は役割ファイルの宣言値です。実効権限については[設計上の注意](#設計上の注意)も確認してください。
`xhigh` は標準とMaxの間に独立した能力境界を作らないため、別roleにはしません。

## ルーティングの仕組み

このリポジトリは、`AGENTS.md` に自然言語のルーティング規則を追加します。
独立した分類器や、D0 から D4 までの判定を機械的に強制するディスパッチャーは導入しません。

親は、次の条件をすべて満たす作業だけを委譲します。

1. 親と独立して進められる。
2. 他の作業と区別できる成果または証拠を返せる。
3. 親のコンテキスト消費か経過時間を減らせる見込みがある。
4. 委譲の調整コストが、親による直接処理より小さい。

分類しただけでは委譲は決まりません。条件を満たさない作業は親が担当します。
委譲は親に与えられた権限を広げません。
回答、レビュー、診断、監視の作業指示（task packet）では、子の能力にかかわらずファイルと外部状態の変更を明示的に禁止します。
標準の推論労力を基本とし、検証範囲、制約の結合、手戻りのリスクなど、必要性を示せる場合に Max を選びます。
Max枠の task packet には、標準の推論労力では誤りや手戻りが増える具体的な理由を含めます。
原子的な D0 を Luna が安価であるという理由だけで分割しません。
同じ入力と完了条件を共有する小さな作業は、分離によって待ち時間、コンテキスト分離、証拠の独立性が改善しない限り、一つの task packet にまとめます。

子は別の子を起動しません。
配布設定は `max_concurrent_threads_per_session = 3` とし、ポリシーも runtime が設定した上限を超える起動を禁止します。
この配布設定を使う場合、親から同時に開ける子スレッドは最大3つです。
同じファイルや状態を更新するエージェントは1つに限定します。

子からの再委譲は、agent TOML と `AGENTS.md` の指示で禁止します。
導入時に除去する旧 `agents.max_depth` は、実効的な強制境界として使用しません。

`NEEDS_ESCALATION` は Codex ランタイムの自動判定ではなく、子が能力不足の根拠を親へ返すための応答規約です。
合理的に選んだ下位役割が返した場合だけ、親はその根拠を確認し、必要な上位役割へ再委譲します。
最初から D2 または D3 と明らかな作業を、昇格結果を得るためだけに Luna へ渡しません。

子を起動するときは、`spawn_agent` の `agent_type` に表の役割名を明示します。`sol_admin_max` には、通常の委譲条件に加えて管理者操作の明示許可が必要です。
`task_name` は子タスクの表示名とパスを付ける項目であり、custom agent の選択には使いません。
`task_name = "luna_task"` だけを指定すると、子が親のモデルと推論労力を継承するため、想定したコスト制御になりません。
D1 から D3 までの委譲では、標準とMax枠のどちらでも `agent_type` を必須とし、まず必ず引数付きで起動します。
委譲条件を満たさない作業は親が直接処理します。
委譲条件を満たすのにtoolが`agent_type`またはcustom agentを明示的に拒否した場合は、親の権限と能力に収まるときだけ親で処理し、runtimeの不一致を報告します。
各 spawn は `fork_turns = "none"` を指定し、親の全会話履歴ではなく task packet だけを子へ渡します。
task packet には権限と変更を許す範囲を含め、再委譲禁止も明記します。

### 待機と作業の終了

各子には、進捗がない時間の上限 `NO_PROGRESS_LIMIT`、終了期限 `HARD_DEADLINE`、安全に中断できる条件 `SAFE_CANCELLATION` を発行時に渡します。
既定値は標準役が10分／30分、Max役が20分／60分です。
進捗がない時間の上限に達したら、親は状況と得られた結果の返却を一度求め、最大2分だけ追加で待ちます。
返却がない場合や終了期限に達した場合は `STALLED` として扱い、変更中の子を安全条件なしに引き取ったり、別の子に同じ書き込みを重複させたりしません。

複数工程の作業では、必須確認 `REQUIRED_ACCEPTANCE_CHECKS`、任意の証拠 `OPTIONAL_EVIDENCE`、終了条件 `STOP_CONDITION` を先に固定します。
必須確認と成果物がそろえば終了し、追加の検証は失敗、新たな対象内リスク、利用者による範囲拡張などの根拠がある場合に限ります。
子の最終返却には `STATUS`、`RESULT`、`EVIDENCE`、`OPEN_ISSUES` を含めます。

## 前提条件

- Windows では PowerShell 7 以降を使用できること。
- Linux では Bash、`awk`、`grep`、`sed`、`cmp` を使用できること。
- カスタムエージェントと subagent workflow に対応した現行 Codex を使用していること。
- この更新で設定読込を確認する Codex CLI 0.149.0、または互換性のある版を使用すること。これを最小対応版の保証とはしません。
- 使用するアカウントで `gpt-5.6-luna`、`gpt-5.6-terra`、`gpt-5.6-sol` を利用できること。
- Astra を親に使う場合は、使用するアカウントとクライアントで `gpt-6-astra` と選択する推論労力を利用できること。
- コマンドをこのリポジトリのルートで実行すること。

導入前に、Codex の起動と設定読込が正常であることを確認してください。

```shell
codex --version
codex doctor --summary --no-color --ascii
```

モデルと推論の選択欄では、親に使う Astra または Sol と、子に使う三つのモデル系統・推論労力を確認します。
Astra の利用可否はアカウント、クライアント、展開状況によって異なります。設定を読み込めることだけでは、モデルの利用権限まで確認できません。[公式 Models 資料](https://learn.chatgpt.com/docs/models#gpt-6-astra)

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
| `agents/sol-admin-max.toml` | 明示許可を必要とする管理者操作用の Sol Max を配置 |
| `rules/task-aware-full-admin.rules` | 直接の管理者昇格コマンドを承認対象にする規則を配置 |

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

親の既定値を Astra Extra High にする場合は、`-SetAstraDefault` を指定します。

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1 -SetAstraDefault
```

従来の Sol xhigh を選ぶ場合は、`-SetSolDefault` を指定します。

```powershell
pwsh -File .\scripts\Install-TaskAwareAgent.ps1 -SetSolDefault
```

両方のモデル選択オプションを同時に指定すると、ファイルを変更する前に停止します。
別の Codex 環境へ試験導入する場合は `-CodexHome <path>`、変更予定だけを確認する場合は `-WhatIf` を指定できます。

PowerShell 版も、`config.toml` がない空の `CODEX_HOME` を初期化できます。

### Linux

標準構成を導入します。

```bash
./scripts/install-task-aware-agent.sh
```

親の既定値を Astra Extra High にする場合は、`--set-astra-default` を指定します。

```bash
./scripts/install-task-aware-agent.sh --set-astra-default
```

従来の Sol xhigh を選ぶ場合は、`--set-sol-default` を指定します。

```bash
./scripts/install-task-aware-agent.sh --set-sol-default
```

両方のモデル選択オプションを同時に指定すると、ファイルを変更する前に停止します。
別の Codex 環境へ導入する場合は、`CODEX_HOME` 環境変数または `--codex-home <path>` を指定できます。
Linux 版は、空の `CODEX_HOME` に必要なファイルを新規作成できます。
Windows 側の checkout を WSL から使う場合は、`.sh` の改行が LF であることを確認してください。
CRLF のまま実行すると、shebang の `bash` を解決できず起動に失敗します。

### 親の推論労力と Ultra

`-SetAstraDefault`／`--set-astra-default` は Astra xhigh、`-SetSolDefault`／`--set-sol-default` は Sol xhigh を設定します。
すでに Astra Max などを選んでいて推論労力を保持したい場合は、モデル選択オプションを付けずに導入してください。

High、Max、Ultra などへ変える場合は、利用するモデルとクライアントの対応を確認して、モデル選択欄または設定で明示的に選びます。
インストーラーは `model_reasoning_effort = "ultra"` を自動では書き込みません。
Ultra を利用できることを、この配布構成の前提条件にはしません。

### 管理者操作用の役割

通常の六役は `approval_policy = "never"` とし、管理者昇格を実行したり要求したりしない指示を持ちます。
`sol_admin_max` だけが `approval_policy = "on-request"` を使い、利用者が操作・対象・権限範囲を明示的に許可した単一作業を担当します。
親は、通常権限で目的を満たせないこと、承認規則が該当する直接の昇格コマンドに `prompt` を返すこと、復旧方法と検証項目があることを確認してから発行します。
不明点や条件の不足があれば、権限を自動で広げず `NEEDS_ESCALATION` を返します。

`danger-full-access` は Codex のコマンド sandbox を外す設定であり、OS の root・管理者権限を与える設定ではありません。
認証には利用者に見える OS のプロンプトやターミナルを使い、チャットでパスワードを受け取ったり `sudo -S` を使ったりしません。

### フルアクセスの影響

`-EnableFullAccess` と `--enable-full-access` は、`approval_policy = "never"` と `sandbox_mode = "danger-full-access"` をグローバル設定へ書き込みます。
Terra の役割ファイルは `workspace-write` を明示しますが、実行環境が親の権限を子へ再適用する場合は、その実効権限にも影響し得ます。
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

どちらの検証スクリプトも、マーカーが正しい順序で一組だけ存在すること、配置されたポリシー・七つの役割ファイル・管理者操作用の規則が配布元と一致することを確認します。
役割ファイルと規則はバイト単位で照合し、主要な設定値、モデルID、推論労力、sandbox、承認ポリシーも静的に確認します。
ポリシーの検査は管理対象のブロック内に限定し、ブロック外に同じ文があっても代用しません。
`codex` コマンドが見つかる場合は、続けて `codex doctor` を実行します。

この検証は、runtime が子へ適用した実効 sandbox、モデルの利用権限、実際の子の起動、D0 から D4 までの分類結果までは確認しません。
導入後は Codex を再起動するか、新しいタスクを開始し、次の手順で実動作も確認してください。

1. 親のモデルと推論の選択欄が、選んだ Astra または Sol と推論労力になっていることを確認する。
2. 一つのファイルから既知の文字列を読むだけの D0 を依頼し、子を起動しないことを確認する。
3. 独立した成果と完了条件があり、委譲条件をすべて満たす D1／D2 を依頼する。標準役とMax役の選択理由、明示した `agent_type`、再委譲しないことを確認する。
4. 単独の D3 は原則として親が担当することを確認する。独立した検証や競合する証拠の判断を委譲する場合は、通常の委譲条件も満たすことを確認する。
5. 各子の詳細を開き、役割・モデル・推論労力・実効権限を個別に確認する。一役の成功を残りの役の実動作確認として扱わない。
6. 管理者操作の明示許可がない依頼では、通常役が昇格を試みず、`sol_admin_max` も発行されないことを確認する。管理者操作の実行確認は、操作固有の許可を得た別の作業として行う。

`AGENTS.md` の指示チェーンは新しい実行の開始時に構築されるため、導入前から開いているタスクでは確認できません。

## 復元

自動アンインストール用のスクリプトはありません。
導入前の状態へ戻す場合は、`$CODEX_HOME/task-aware-backups/<timestamp>/` に保存されたファイルを元の場所へ戻します。

再導入している場合、最新のバックアップが初回導入前の状態とは限りません。
戻したい導入時に表示された `Backup:` のパスを選び、初回導入前へ戻す場合は初回のバックアップを使ってください。
導入後に `config.toml` や `AGENTS.md` を変更している場合は、バックアップをそのまま上書きせず、差分を確認して task-aware 関連の設定だけを手動で統合してください。

導入前に存在しなかったファイルはバックアップへ含まれません。
その場合は、七つのエージェントファイルと `rules/task-aware-full-admin.rules` のうち今回新規に追加されたもの、`AGENTS.md` の `BEGIN CODEX TASK-AWARE AGENT` から `END CODEX TASK-AWARE AGENT` までのブロックを手動で取り除く必要があります。
既存だった役割や規則は削除せず、戻したい時点のバックアップを使います。

## ファイル構成

- `config/AGENTS.task-aware.md`：グローバル指示へ追加するルーティング規則
- `config/config.task-aware.toml`：`config.toml` へ統合する設定例
- `agents/*.toml`：Luna、Terra、Sol の役割別エージェント
- `rules/full-admin.rules`：管理者昇格の承認規則。導入先では `rules/task-aware-full-admin.rules`
- `scripts/Install-TaskAwareAgent.ps1`：バックアップ付き導入スクリプト
- `scripts/Test-TaskAwareAgent.ps1`：配置と Codex 設定の検証スクリプト
- `scripts/install-task-aware-agent.sh`：Linux 向けのバックアップ付き導入スクリプト
- `scripts/test-task-aware-agent.sh`：Linux 向けの配置と Codex 設定の検証スクリプト

## 指示の保守

配布する管理ブロックの編集元は `config/AGENTS.task-aware.md` です。同じ条件は既存の規則へ統合し、経緯、例、詳細な手順はREADMEや作業記録に置きます。導入済みのコピーだけを編集すると、次の導入で配布元の内容へ戻ります。

管理ブロックはUTF-8で10 KiB以下を保守上の上限とし、検証スクリプトとCIで超過を検出します。これは本プロジェクトの分量管理で、Codex本体の読み込み上限ではありません。利用者が管理ブロック外に書いた指示には、この上限を適用しません。

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
- Max は応答時間と token 使用量を増やすため、標準 effort で十分な作業には使いません。
- Astra を親にしても、子の発行条件、モデル、権限境界は変わりません。
- モデルが利用できることと、ルーティングが適切であることは静的テストだけでは保証できません。
- ルーティングは親の判断に依存するため、D0 から D4 までの境界は決定的ではありません。
- Codex Desktop や CLI の実効 permission profile が親の権限を子へ強制する runtime では、role TOML の `sandbox_mode` より親の実効権限が優先される場合があります。Luna と Sol Specialist の developer instructions も書き込みを禁止しますが、これは OS sandbox と同じ強制境界ではありません。
- 管理者操作用のコマンド規則は、直接のコマンド入口に対する承認制御です。shell wrapper や間接実行のすべてを捕捉する仕組みではありません。強い隔離が必要な場合は、別の OS アカウント、コンテナ、VM、限定した権限仲介などを使います。

## 参考資料

- [Models](https://learn.chatgpt.com/docs/models)
- [Codex rate card](https://help.openai.com/en/articles/20001106-codex-rate-card)
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Configuration Reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Configuration Schema](https://developers.openai.com/codex/config-schema.json)
- [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex changelog](https://learn.chatgpt.com/docs/changelog)
