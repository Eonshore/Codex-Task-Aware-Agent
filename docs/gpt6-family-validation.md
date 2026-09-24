# GPT-6 ファミリー移行の検証記録

検証日: 2026-09-24。対象は `codex/merge-astra-local` の `0ac314a` を基底にした GPT-6 ファミリー割り当てです。

## 設定と移行

- 全十役の TOML を解析し、モデルと effort の組を同日のモデルカタログで確認。
- Codex CLI 0.156.1 で strict config load と管理者規則の `prompt` 評価を確認。昇格コマンド自体は実行していません。
- Linux CI の clean-home、既存設定保持、再導入、旧設定移行、marker/CRLF、drift、fault injection、10 KiB 上限の検査を実行。
- 旧全 Astra 構成から D1/D2 のモデルが更新され、親の model/effort、権限、独自役割、旧設定のバックアップが保持されることを確認。
- 誤った D1 モデルと、D1/D2 を全 Astra に戻した構成が validator に拒否されることを確認。
- Bash 構文と `git diff --check` を確認。Windows の PowerShell 構文・round trip は GitHub Actions の Windows job で確認します。

## 実起動

既存のグローバル設定を変更せず、一時 `CODEX_HOME` へ導入して認証済みの新しい CLI タスクを開始しました。
親は Astra Low / read-only。変更対象の五役を `agent_type` と `fork_turns = "none"` で一つずつ起動し、モデル・effort の上書きや代替役へのフォールバックは行っていません。
各子には再委譲・ツール・書き込みを禁止し、固定文字列 `FAMILY_PROBE_OK` の返却だけを依頼しました。
返却結果に加え、各子の実行記録の `turn_context` でモデル・effort・sandbox を確認しました。

| 役割 | 実モデル | effort | 実効 sandbox | 結果 |
| --- | --- | --- | --- | --- |
| `luna_task` | `gpt-6-luna` | low | read-only | 応答成功 |
| `luna_task_medium` | `gpt-6-luna` | medium | read-only | 応答成功 |
| `luna_task_max` | `gpt-6-luna` | high | read-only | 応答成功 |
| `terra_worker` | `gpt-6-sol` | medium | read-only（親から継承） | 応答成功 |
| `terra_worker_max` | `gpt-6-sol` | high | read-only（親から継承） | 応答成功 |

最初の CLI 0.154.0 では、五役とも GPT-6 Luna/Sol が ChatGPT アカウントで未対応という HTTP 400 を返しました。
同じアカウントで CLI 0.156.1 を一時領域に導入すると、モデル一覧に Luna/Sol が現れ、上記五役が応答しました。
この差を受け、CI の固定バージョンを 0.156.1 に更新しています。0.154.0 の設定読込成功は、モデル利用可能性の証拠にはなりません。

この probe は役割の読込・モデル選択・応答の確認です。D0-D4 の自律分類、実装品質、消費量、速度、書き込み時の sandbox、変更していない Astra 役の再評価は対象外です。
管理者役は起動していません。全役の分類評価と管理者操作の実動作は、公開チェックリスト上の別確認です。

参照: [公式のモデル選択案内](https://learn.chatgpt.com/docs/models)、[GPT-6 ファミリーの案内](https://developers.openai.com/api/docs/guides/latest-model)。役割への割り当ては本プロジェクトの方針であり、モデル間の性能比較結果ではありません。
