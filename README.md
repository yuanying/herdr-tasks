# herdr-tasks

herdr の workspace / worktree を使って、与えられたタスクを
完遂まで面倒を見る Coding Agent 向けスキル。

タスクを受け取ったら専用の workspace を作り、そこに常駐する **coordinator** にタスク完遂までの
責任を持たせる。対象が複数リポジトリにまたがる場合は、リポジトリごとに worktree を切って
**worker** を立て、coordinator がそれらを取りまとめる。

特定の Coding Agent に依存しない。`herdr` CLI と `git`、`ghq` があれば動く。

## 何が起きるか

```
呼び出し元 (現在の pane)
  │  タスク仕様書を書き、coordinator を起動して手を引く
  ▼
coordinator workspace                    ~/.local/state/herdr-tasks/<タスク名>/
  │  タスク完遂までの責任を持つ            TASK.md / PROGRESS.md / notes/
  ├─▶ worker workspace (リポジトリ A の worktree)
  └─▶ worker workspace (リポジトリ B の worktree)
```

- 対象リポジトリが coordinator のいるリポジトリ 1 つだけなら、worker は立てず coordinator が自分で実装する。
- coordinator と worker は別プロセスであり、会話文脈は引き継がれない。渡せるのはファイルのパスだけである。
  そのためタスク仕様書 `TASK.md` の質がそのままタスクの成否を左右する。
- 完遂の定義は「実装 + テスト通過 + コミット」まで。push と PR 作成は人が判断する。
- coordinator は worker の完了報告を鵜呑みにせず、`git log` / `git diff` とテストの再実行で自ら検証する。

## インストール

```bash
ghq get github.com/yuanying/herdr-tasks
cd "$(ghq root)/github.com/yuanying/herdr-tasks"
./scripts/install-skill.sh
```

`~/.agents/skills/herdr-tasks` と `~/.claude/skills/herdr-tasks` にこのリポジトリへの symlink を張る。
既にある場合は何もしない。別の実体が置かれている場合は、何も変更せずに中止する。

## 使い方

Coding Agent に `herdr-tasks` スキルを使うよう伝える。以降はスキルが、タスク名の決定から
仕様書の作成、対象リポジトリの特定、workspace の作成、coordinator の起動までを行う。

起動後、進捗は coordinator が持つ。様子を見るときは coordinator の pane を覗く。

```bash
herdr agent list
herdr agent attach <coordinator の agent 名>
```

## 構成

| ファイル | 内容 |
|---|---|
| `SKILL.md` | 呼び出し元の手順と全体像、命名規則 |
| `coordinator.md` | coordinator が読む手順書 |
| `worker.md` | worker が読む手順書 |
| `scripts/install-skill.sh` | symlink を張る |
| `docs/adr/` | 設計判断の記録 |

## 命名規則

タスク名を 1 つ決め、そこからすべてを導出する。

| 用途 | 例 |
|---|---|
| タスク名 | `#42-add-retry-to-uploader` |
| coordinator workspace | `#42-add-retry-to-uploader` |
| worker workspace | `#42-add-retry-to-uploader/herdr` |
| ブランチ | `issue-42-add-retry-to-uploader` |
| タスクディレクトリ | `~/.local/state/herdr-tasks/#42-add-retry-to-uploader/` |
| agent 名 | `coord-42-add-retry` / `work-42-herdr` |

詳細は [`SKILL.md`](SKILL.md) を参照。設計の背景と判断の理由は
[`docs/adr/0001-herdr-tasks-skill-architecture.md`](docs/adr/0001-herdr-tasks-skill-architecture.md) にある。
