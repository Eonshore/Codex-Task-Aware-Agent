# 公開チェックリスト

## 公開候補

- [ ] `main` が最新の `origin/main` と一致し、working tree に意図しない変更がない。
- [ ] [Codex changelog](https://learn.chatgpt.com/docs/changelog) で最新版を確認し、`.github/workflows/ci.yml` と README の検証基準を更新する。
- [ ] [Codex Models](https://learn.chatgpt.com/docs/models) と [Astra guide](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra) で、モデル、effort、委譲方針の互換性を確認する。
- [ ] `CHANGELOG.md` の version、日付、release link を確定する。
- [ ] `LICENSE`、`SECURITY.md`、`CONTRIBUTING.md` が release archive に含まれる。
- [ ] GitHub Actions の Windows/Linux job が成功する。
- [ ] 認証済みの新しい Codex task で D0 の no-spawn、D1 の Low/Medium/High 条件と D2/D3/D4 の標準・上位条件を実行する。子の実起動を通じて、model がすべて `gpt-6-astra`、effort が D1 の Low/Medium/High、D2 の Medium/High、D3 の High/xhigh、D4 の xhigh/Max になっていることを確認する。
- [ ] D4 の入力に2件以上の独立した D3 所見が含まれ、D4 も読み取り専用・再委譲禁止・同時に最大3子を守ることを確認する。
- [ ] 親の Astra xhigh 設定、標準導入での既存親設定の維持、廃止した Sol オプションの案内と変更前の停止を確認する。
- [ ] 上位枠が能力境界や sandbox を広げず、task packet に昇格理由が含まれることを確認する。
- [ ] 管理者許可がない場合は通常役が昇格を試みず、`sol_admin_max` も発行されない。規則の直接入口が `prompt` と評価されることを、昇格コマンドを実行せず確認する。
- [ ] 管理者役も `gpt-6-astra`／`max` とし、専用の承認条件を維持する。
- [ ] Windows/Linux でマーカーの一意性・順序、ポリシー・十役・規則のバイト一致、CRLF、差異、不正マーカーを確認する。
- [ ] v3.1 の判断順、期限、必須・任意確認、終了条件が管理ブロック外の記述で代用できず、10 KiB 超過も検出される。
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
