# herdr-tasks

herdr の workspace / worktree を使って、与えられたタスクを
完遂まで面倒を見る Coding Agent 向けスキル。

タスクを受け取ったら **1 タスク = 1 workspace** の専用 workspace を作り、その root tab に
常駐する **coordinator** にタスク完遂までの責任を持たせる。作業対象ごとに同じ workspace 内へ
リポジトリ別の worktree tab を作って **worker** を立て、coordinator がそれらを取りまとめる。

特定の Coding Agent に依存しない。`herdr` CLI と `git`、`ghq` があれば動く。

## 何が起きるか

```
呼び出し元 (現在の pane)
  │  タスク仕様書を書き、coordinator を起動して手を引く
  ▼
task workspace
  ├─ coordinator root tab
  ├─ worker tab (リポジトリ A の worktree)
  └─ worker tab (リポジトリ B の worktree)
```

タスクの状態はすべて固定パスのタスクディレクトリに残る。

```
~/.local/state/herdr-tasks/<タスク名>/
  ├─ TASK.md          仕様。coordinator が受け取る唯一の文脈（まれに変わる）
  ├─ STATE.md         状態表・次にやること・未解決の要判断（毎回上書き）
  ├─ PROGRESS.md      日付つきの時系列（追記のみ）
  ├─ notes/           判断の経緯
  │   └─ workers/     worker ごとの指示ファイル
  └─ worktrees/       worker の作業ツリー
```

- 呼び出し元と作業対象が同じリポジトリの場合だけ、coordinator がその worktree を担当できる。
- 呼び出し元と作業対象が異なる場合は、対象が 1 リポジトリでも必ず worker tab を作る。
- 複数リポジトリでも workspace は増やさず、リポジトリ別 tab としてまとめる。
- coordinator と worker は別プロセスであり、会話文脈は引き継がれない。渡せるのはファイルのパスだけである。
  そのためタスク仕様書 `TASK.md` の質がそのままタスクの成否を左右する。
- 完遂の定義は「実装 + テスト通過 + コミット + push + PR」まで。PR は作業単位ごとに、
  それを担当した worker が出す。マージはユーザーの承認を得てから行う。
- coordinator は worker の完了報告を鵜呑みにせず、`git log` / `git diff` とテストの再実行で自ら検証する。
- coordinator の会話文脈が失われても、タスクディレクトリの記録から再開できる。worker への指示も
  ファイルに残るため、再開に呼び出し元の会話文脈は要らない。
- 記録は **変更頻度で分けてある。** 再開時に必ず読むのは TASK.md と STATE.md の 2 つで、
  伸び続ける PROGRESS.md は必要なときだけ日付で引く。
- 記録は決定に覆されて古くなる。**覆した coordinator が、その場で記録を訂正する。**
  古い記述は消さず、いまの前提を TASK.md の「現在地」に書いて優先させる。

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
| `scripts/prompt-agent.sh` | agent の入力待ちとプロンプト着弾を判定する |
| `docs/adr/` | 設計判断の記録 |

## 命名規則

タスク名を 1 つ決め、そこからすべてを導出する。

| 用途 | 例 |
|---|---|
| タスク名 | `#42-add-retry-to-uploader` |
| coordinator workspace | `#42-add-retry-to-uploader` |
| worker tab | `herdr` |
| ブランチ | `issue-42-add-retry-to-uploader` |
| タスクディレクトリ | `~/.local/state/herdr-tasks/#42-add-retry-to-uploader/` |
| agent 名 | `coord-42-add-retry` / `work-42-herdr` |

詳細は [`SKILL.md`](SKILL.md) を参照。設計の背景と判断の理由は
[`docs/adr/0001-herdr-tasks-skill-architecture.md`](docs/adr/0001-herdr-tasks-skill-architecture.md) にある。
