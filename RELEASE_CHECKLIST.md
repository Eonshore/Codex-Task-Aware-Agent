# 公開チェックリスト

## 公開候補

- [ ] `main` が最新の `origin/main` と一致し、working tree に意図しない変更がない。
- [ ] [Codex changelog](https://learn.chatgpt.com/docs/changelog) で最新版を確認し、`.github/workflows/ci.yml` と README の検証基準を更新する。
- [ ] [Models](https://learn.chatgpt.com/docs/models#gpt-6-astra) で Astra と必要な子モデルの対応条件を確認する。価格の比較を掲載する場合は、公式の現行料金も確認する。
- [ ] `CHANGELOG.md` の version、日付、release link を確定する。
- [ ] `LICENSE`、`SECURITY.md`、`CONTRIBUTING.md` が release archive に含まれる。
- [ ] GitHub Actions の Windows/Linux job が成功する。
- [ ] Windows/Linux の Astra 選択オプションが `gpt-6-astra`／`xhigh` を設定し、標準導入が既存の親モデル・推論労力・権限・非管理設定を保持する。
- [ ] 従来の Sol 選択が動作し、Astra と Sol の同時指定がファイル変更前に拒否される。
- [ ] 認証済みの新しい Codex task で Astra 親を確認する。D0 の no-spawn、委譲条件を満たす D1/D2 と例外的な D3 について、Luna Low/Max、Terra Medium/Max、Sol High/Max のモデルと推論労力を個別に確認する。
- [ ] Max枠が能力境界や sandbox を広げず、task packet に昇格理由が含まれることを確認する。
- [ ] 管理者許可がない依頼では通常役が昇格を試みず、`sol_admin_max` も発行されない。規則の直接入口が `prompt` と評価されることは、昇格コマンドを実行せずに確認する。
- [ ] Windows/Linux の検証スクリプトでマーカーの一意性と順序、配置されたポリシーと配布元の一致、七役と規則のバイト単位での一致を確認する。
- [ ] マーカーの重複・順序異常、ポリシー・役割・規則の差異を個別に注入し、各不正状態を検出する。
- [ ] v3.1 の判断順序、作業指示の有限期限、必須確認と終了条件が、管理ブロック外の記述では代用できないことを確認する。
- [ ] `git diff --check` と秘密情報 scan を通す。

## 公開

管理者操作そのものの実行確認が必要な場合は、操作・対象・昇格方法・復旧方法について別途許可を得て実施します。
ファイルの一致や `config.load = ok` だけで、全役の実動作や管理者操作の成功を主張しません。

annotated tag を作り、tag だけを push します。例は初回 release です。

```shell
git tag -a v0.1.0 -m "Codex Task-Aware Agent v0.1.0"
git push origin v0.1.0
```

tag push 後、Release workflow が validation、archive、checksum、GitHub Release 作成を順に行います。

## 公開後

- [ ] GitHub Release の zip と tar.gz を取得し、`SHA256SUMS` と一致する。
- [ ] clean home へ release archive から導入し、validator を再実行する。
- [ ] repository の public visibility、Security advisory、issue template、default branch protection を確認する。
- [ ] README badge と release link が公開状態で解決する。
