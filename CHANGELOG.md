# 変更履歴

このプロジェクトは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) の形式と [Semantic Versioning](https://semver.org/lang/ja/) に従います。

## [Unreleased]

### 変更

- 現行の価格差を踏まえ、Luna Low の D1 を固定入力、明示的な出力契約、客観的完了条件を持つ限定的な読み取り専用調査・検証まで拡張。
- Terra Medium の D2 を、状態変更を伴う実装、tool-heavy な複数工程、通常判断が必要な調査・検証として明確化。
- D1 に Luna Max、D2 に Terra Max、D3 に Sol Max の上位 variant を追加。
- 中間の xhigh role は設けず、標準とMaxの二段階に統一。
- 能力クラスを先に決め、同じクラス内で標準またはMax枠を選ぶ二段階ルーティングへ変更。
- 価格低下を、Maxによる完全性向上または手戻り回避を選びやすくする根拠として反映。
- 最小十分な役割を選びつつ、D0 の細分化、明白な D2/D3 の意図的な過小ルーティング、不要な microtask fan-out を禁止。
- 価格低下後も、統合負荷と競合を抑えるため同時に開く子スレッドの上限を3つに維持。

### 検証

- Windows/Linux validator に、価格対応後の D1/D2 境界と過剰委譲防止規則の検査を追加。
- Windows/Linux installer と validator を六 role の配置、model、effort、sandbox 検査へ拡張し、旧Luna/Terra High roleをbackup後に除去する移行を追加。
- release 前の live probe を、六 role の model/effort 確認と D0 から D3 までの標準・Maxルーティング確認へ拡張。

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
