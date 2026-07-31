# 公開チェックリスト

## 公開候補

- [ ] `main` が最新の `origin/main` と一致し、working tree に意図しない変更がない。
- [ ] [Codex changelog](https://learn.chatgpt.com/docs/changelog) で最新版を確認し、`.github/workflows/ci.yml` と README の検証基準を更新する。
- [ ] [Codex rate card](https://help.openai.com/en/articles/20001106-codex-rate-card) でモデル間の価格差を確認し、ルーティング根拠が現行レートと矛盾しない。
- [ ] `CHANGELOG.md` の version、日付、release link を確定する。
- [ ] `LICENSE`、`SECURITY.md`、`CONTRIBUTING.md` が release archive に含まれる。
- [ ] GitHub Actions の Windows/Linux job が成功する。
- [ ] 認証済みの新しい Codex task で D0 の no-spawn、D1/D2/D3 の標準・Max条件を実行し、Luna Low/Max、Terra Medium/Max、Sol High/Max の model と reasoning effort を live probe する。
- [ ] Max枠が能力境界や sandbox を広げず、task packet に昇格理由が含まれることを確認する。
- [ ] `git diff --check` と秘密情報 scan を通す。

## 公開

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
