# workflows

個人プロジェクト向けの再利用可能な GitHub Actions
ワークフローとコンポジットアクション集。

## Reusable Workflows

| Workflow | 説明 |
| --- | --- |
| `release-on-version-change.yml` | バージョン変更を検知し GitHub Release を作成 |
| `claude.yml` | Issue/PR での `@claude` メンションに応答 |
| `claude-code-review.yml` | ラベル付き PR の自動コードレビュー |
| `issue-scan.yml` | Claude による open issue のトリアージ |
| `issue-implement.yml` | Claude による issue の自動実装 |
| `dependabot-scan.yml` | `pnpm audit` で脆弱性を検出し Issue 管理 |

## 本リポジトリ専用ワークフロー

| Workflow | 説明 |
| --- | --- |
| `workflow-lint.yml` | actionlint + zizmor によるワークフロー静的解析 |

## Composite Actions

| Action | 説明 |
| --- | --- |
| `resolve-version` | package.json / pyproject.toml / Cargo.toml / VERSION からバージョン取得 |
| `release-core` | Git タグと GitHub Release を作成（冪等） |
| `audit-scan` | audit JSON を解析し脆弱性 Issue を管理 |

## 使い方

```yaml
jobs:
  release:
    uses: >-
      rysk-tanaka/workflows/.github/workflows/
      release-on-version-change.yml@main
    secrets: inherit
```

## Renovate 共有プリセット

リポジトリ直下の `default.json` は Renovate の共有プリセット。
各リポジトリの `renovate.json` から次のように読み込む。

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>rysk-tanaka/workflows"],
  "enabledManagers": ["cargo", "github-actions"]
}
```

プリセットに含まれる設定は次のとおり。

| 設定 | 値 |
| --- | --- |
| `extends` | `config:recommended`, `helpers:pinGitHubActionDigests` |
| `minimumReleaseAge` | `3 days`。公開から 3 日経つまで更新 PR を作らない |
| `schedule` | `before 9am on saturday` |
| `timezone` | `Asia/Tokyo` |
| `labels` | `dependencies` |
| `packageRules` | minor / patch を自動マージ、`rysk-tanaka/workflows` の digest 更新を自動マージ |

`rysk-tanaka/workflows` の reusable workflow は `@<main のコミット SHA> # main` で固定して呼び出すため、
更新は digest 更新になり minor / patch のルールでは自動マージされない。
そのため digest 更新を自動マージするルールを別に入れている。
ブランチの digest にはリリース日時がなく、`minimumReleaseAge` を残すと `renovate/stability-days` が
pending のまま自動マージされないため、このルールでは `minimumReleaseAge` を外している。
自動マージを止めたいリポジトリでは、`matchDepNames: ["rysk-tanaka/workflows"]` に
`automerge: false` を指定して上書きする。更新 PR 自体を止める場合は `enabled: false` を指定する。

`enabledManagers`、パッケージのグループ化、特定パッケージの無効化など、
リポジトリ固有の設定は各リポジトリの `renovate.json` に書く。
`packageRules` はプリセットの後ろに追加されるので、
プリセットの自動マージを一部のマネージャーだけ止めたい場合は次のように上書きする。

```json
{
  "packageRules": [
    {
      "matchManagers": ["github-actions"],
      "automerge": false
    }
  ]
}
```

### プリセットのコミット SHA 固定

`github>rysk-tanaka/workflows` と書くと、Renovate は実行のたびに main にある `default.json` を読む。
main を書き換えられると、スケジュールや `minimumReleaseAge` を外した設定がすべてのリポジトリに
次の実行から効き、reusable workflow を SHA で固定して確保した待ち時間がなくなる。
これを避けるには、`#` の後ろにコミット SHA を書いてプリセットを固定する。

```json
{
  "extends": ["github>rysk-tanaka/workflows#<main のコミット SHA>"]
}
```

- `#` の後ろの値は GitHub の Contents API に `ref` として渡されるため、コミット SHA も使える。
  ただし Renovate のドキュメントに書かれているのはタグだけで、SHA の指定は記載のない使い方になる
- タグ（`#v1` など）は付け替えられるので、main を書き換えられる相手には固定の効果がない
- 固定した SHA は Renovate が自動では更新しないため、プリセットを変えたら各リポジトリで手動で上げる

### minimumReleaseAge の注意点

- `lockFileMaintenance` には効かない。ロックファイルの更新はパッケージマネージャーに任せるため、
  Renovate がリリース日時を確認できない。既定の `minimumReleaseAgeBehaviour=timestamp-required` では
  `renovate/stability-days` チェックが pending のまま残るので、自動マージされず手動でのマージになる。
  ロックファイル経由で入る間接依存の待ち時間は、pnpm の `minimumReleaseAge` など
  パッケージマネージャー側の設定で補う
- セキュリティ修正の更新は待ち時間なしで作られる
- ghcr.io などリリース日時を取得できないレジストリの依存は、既定では更新 PR が作られない

### プリセット変更時の確認

`default.json` の変更は、SHA で固定せずに読み込んでいるリポジトリには次回の Renovate 実行から反映される。
変更後は各リポジトリの Dependency Dashboard や Renovate のログで、設定が意図どおり読み込まれていることを確認する。

## セットアップ

プライベートリポジトリの場合は
**Settings > Actions > General > Access** で
**「Accessible from repositories owned by the user
'rysk-tanaka'」** を有効にしてください。
