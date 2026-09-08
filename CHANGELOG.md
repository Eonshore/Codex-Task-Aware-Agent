# 変更履歴

このプロジェクトは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) の形式と [Semantic Versioning](https://semver.org/lang/ja/) に従います。

## [Unreleased]

### 追加

- 親モデルとして Astra（`gpt-6-astra`）に対応。Windows の `-SetAstraDefault` と Linux の `--set-astra-default` で Astra xhigh を明示的に選択できる。
- 現行運用の管理者操作用 `sol_admin_max` と承認規則を配布。操作・対象・権限範囲の明示許可を必須とし、通常役からの自動昇格を禁止する。
- 子の作業指示に有限の `NO_PROGRESS_LIMIT`、`HARD_DEADLINE`、`SAFE_CANCELLATION` と最終返却の形式を定義。
- 複数工程の必須確認、任意の証拠、終了条件を先に固定し、検証範囲を追加できる条件を定義。

### 変更

- 常時読み込む委任ポリシーの重複を統合し、判断順序、役割、権限、検証の終了条件、有限の待機を維持したまま短縮。管理ブロックに10 KiBの保守上限を設け、追記による再肥大化を検証で検出する。
- 配布ポリシーを現行の v3.1 に更新。権限範囲を固定し、能力分類、委譲可否の判定、役割・推論労力の選択の順に処理する。
- D1 は固定入力、明示的な出力契約、客観的完了条件を持つ限定的な読み取り専用作業とする。
- D2 は範囲と完了条件が明確な状態変更を伴う実装・修復・統合とし、通常判断が必要という理由だけで読み取り専用調査を Terra へ送らない。
- 単独の D3 は原則として親が担当し、Sol への委譲には独立した判断・証拠の価値と通常の委譲条件の両方を求める。
- D1 に Luna Max、D2 に Terra Max、D3 に Sol Max の上位 variant を追加。
- 標準とMaxの二段階を維持し、検証範囲、制約の結合、手戻りなどの具体的な必要性に基づいて Max を選ぶ。中間の xhigh role は設けない。
- 通常の六役は管理者昇格を拒否し、`approval_policy = "never"` を明示。Terra の二役には `sandbox_mode = "workspace-write"` を明示。
- D0 の細分化、明白な D2/D3 の意図的な過小ルーティング、不要な小作業への分割を禁止。
- ポリシーから価格、固定スレッド数、旧ランタイム版に依存する説明を外し、実行環境の同時起動上限を尊重する。配布設定の上限は子3つを維持。
- 委譲が親の権限を広げないよう、作業指示に権限と変更を許す範囲を追加。
- 標準導入で親モデル・推論労力・権限を保持し、従来の Sol xhigh 選択も維持。Astra と Sol の同時選択は変更前に拒否する。
- README を Astra の導入手順と七役に更新し、Ultra を前提にした説明を改める。

### 検証

- Windows/Linux の導入・検証処理を七役と管理者操作用の規則へ拡張。旧 Luna/Terra High role はバックアップ後に除去する。
- マーカーの一意性・順序、配置されたポリシーと配布元の一致、七役と規則のバイト単位での一致を検査する。
- v3.1 の判断順序、権限境界、有限の待機・終了条件を、管理対象のポリシーブロック内で検査する。
- 隔離した `CODEX_HOME` で Astra/Sol の選択、既存設定保持、相互排他、再導入、バックアップ、不正なマーカーやファイルの差異の検出を確認する回帰テストを追加。
- リリース時の実動作確認を、Astra 親、委譲条件を満たした標準・Max役、管理者許可がない場合の拒否へ更新。設定の一致とモデルの実行確認を分けて記録する。

## [0.1.0] - 2026-07-26

初回の公開候補です。

### 追加

- D0 から D4 までの task-aware delegation policy。
- Luna Low、Terra Medium、Sol High の custom agent 定義。
- Windows/Linux の backup 付き installer と validator。
- Windows/Linux の clean-home CI、週次の最新 Codex 互換性確認。
- tag から source archive と SHA-256 checksum を作る release workflow。

### 変更

- 現行 Codex V2 に合わせ、`agents.max_concurrent_threads_per_session = 3` を使用。
- legacy の `features.multi_agent`、`agents.max_threads`、`agents.max_depth` を導入時に除去。
- Ultra を reasoning effort ではなく subagent execution mode として説明。

### 修正

- Windows installer が空の `CODEX_HOME` を初期化できない問題。
- Windows validator が指定された `CODEX_HOME` 以外を doctor していた問題。
- `default_permissions` と full-access 設定の競合を見逃す問題。
- 公開用 policy から `fork_turns = "none"` と task packet の再委譲禁止が欠落していた問題。
- malformed/duplicate marker による `AGENTS.md` の破損と、同一秒の再導入による Windows backup 衝突。
- コメント付き TOML table header とインデントされた key を重複生成する問題。
- release tag と `CHANGELOG.md` の version 不一致を公開前に止めない問題。

[0.1.0]: https://github.com/Eonshore/Codex-Task-Aware-Agent/releases/tag/v0.1.0
