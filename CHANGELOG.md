# 変更履歴

このプロジェクトは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) の形式と [Semantic Versioning](https://semver.org/lang/ja/) に従います。

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
