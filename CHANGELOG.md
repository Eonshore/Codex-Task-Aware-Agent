# 変更履歴

このプロジェクトは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) の形式と [Semantic Versioning](https://semver.org/lang/ja/) に従います。

## [Unreleased]

### 追加

- 親モデルとして Astra（`gpt-6-astra`）に対応。Windows の `-SetAstraDefault` と Linux の `--set-astra-default` で Astra xhigh を明示的に選択できる。
- 現行運用の管理者操作用 `sol_admin_max` と承認規則を配布。操作・対象・権限範囲の明示許可を必須とし、通常役からの自動昇格を禁止する。
- 子の作業指示に有限の `NO_PROGRESS_LIMIT`、`HARD_DEADLINE`、`SAFE_CANCELLATION` と最終返却の形式を定義。
- 複数工程の必須確認、任意の証拠、終了条件を先に固定し、検証範囲を追加できる条件を定義。

### 変更

- 配布ポリシーを v3.1 に更新し、判断順、権限、有限期限、必須確認と終了条件を統合。管理ブロックの 10 KiB 上限を維持。
- 親の導入オプションは GPT-6 Astra xhigh。子は D1 を GPT-6 Luna Low/Medium/High、D2 を GPT-6 Sol Medium/High、D3 を GPT-6 Astra High/xhigh、D4 を GPT-6 Astra xhigh/Max に更新。管理者専用役は Astra Max を維持。
- 既存六役の名前とファイル名を維持。`_max` は上位枠の識別名とし、D1・D2 は High、D3 は xhigh、D4 は Max に対応。
- D1 の軽い突き合わせ向けに `luna_task_medium` を追加。標準 Low・Medium と上位 High の選択基準を明確化。
- D4 の所見統合用に `astra_architect` / `astra_architect_max` を追加。2件以上の独立した D3 所見を入力とし、読み取り専用・再委譲禁止・最大3子を維持。
- Astra xhigh を親へ設定する `--set-astra-default` / `-SetAstraDefault` を追加。通常導入は既存の親モデル、effort、権限を維持。
- 旧 Sol 既定値オプションを廃止。指定時は Astra オプションへの案内を表示し、ファイル変更前に停止。
- 能力クラスを先に決め、同じクラス内で標準または上位枠を選ぶ二段階ルーティングへ変更。D1 の限定的な読み取り専用調査と、D2 の通常判断を伴う実装・調査の境界を明確化。
- 委譲の条件を満たす場合の実行、承認済み作業の継続、変更範囲に応じた検証をポリシーへ追加。
- D0 の細分化、明白な D2/D3 の意図的な過小ルーティング、不要な小タスクへの分割を禁止。子は最大3つ、再委譲禁止を維持。

### 検証

- マーカーの完全一致・順序・一意性、配布ポリシー・十役・規則のバイト一致を検査。CRLF、ブロック外の記述、不正なマーカー、期限や終了条件の欠落、差異、10 KiB 超過を回帰検証する。

- CI の固定バージョンを、GPT-6 ファミリー設定を検証する Codex CLI 0.156.1 へ更新。
- Windows/Linux validator を十役の model、effort、sandbox、承認ポリシーと GPT-6 ファミリーの割り当ての検査へ更新。
- Windows/Linux installer に、旧 Luna/Terra High role を backup 後に除去する移行を追加。
- CI に親の設定維持、Astra opt-in、廃止した Sol オプションの停止と再導入の検査を追加。
- 全 Astra 構成からの再導入で D1/D2 のモデルを更新し、既存の親・権限・独自役割・バックアップを保持する移行と、誤ったモデル割り当ての拒否を検証。
- リリース前の実動作確認を、九役の model/effort と D0 から D4 の役割選択へ拡張。静的検査とモデル起動の検証を区別。

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
