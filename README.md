# herdr-tasks

herdr の workspace / worktree を使って、与えられたタスクを
完遂まで面倒を見る Coding Agent 向けスキル。

タスクを受け取ったら **1 タスク = 1 workspace** の専用 workspace を作り、その root tab に
常駐する **coordinator** にタスク完遂までの責任を持たせる。作業対象ごとに同じ workspace 内へ
リポジトリ別の worktree tab を作って **worker** を立て、coordinator がそれらを取りまとめる。
タスクが増えたら、全タスクを束ねる **supervisor** を 1 つだけ常駐させ、一覧とタスク横断の
関係を持たせる。

特定の Coding Agent に依存しない。`herdr` CLI と `git`、`ghq` があれば動く。

## 何が起きるか

```
呼び出し元 (現在の pane、または supervisor)
  │  タスク仕様書を書き、coordinator を起動して手を引く
  ▼
task workspace
  ├─ coordinator root tab (タスクディレクトリ)
  ├─ worker tab (リポジトリ A の worktree)
  └─ worker tab (リポジトリ B の worktree)

herdr-supervisor workspace (全体で 1 つ)
  └─ supervisor root tab (supervisor ディレクトリ)
       │  聞かれたときだけ全タスクを読む。取り次ぎ・立て直しはユーザー確認後
       ├─▶ task workspace A の coordinator
       └─▶ task workspace B の coordinator
```

タスクの状態はすべて固定パスのタスクディレクトリに残る。

```
~/.local/state/herdr-tasks/<タスク名>/
  ├─ AGENTS.md        役割の見分け方と読むべき手順書。セッション開始時に読み込まれる
  ├─ CLAUDE.md        AGENTS.md を @ で読み込むだけ
  ├─ TASK.md          仕様。coordinator が受け取る唯一の文脈（まれに変わる）
  ├─ STATE.md         状態表・次にやること・未解決の要判断（毎回上書き）
  ├─ PROGRESS.md      日付つきの時系列（追記のみ）
  ├─ notes/           判断の経緯
  │   └─ workers/     worker ごとの指示ファイル
  └─ worktrees/       worker の作業ツリー
```

`STATE.md` の 1 行目は `状態: 進行中|要判断|完遂|中止` の状態行である。supervisor は
この 1 行だけで全タスクを分類する。

supervisor の記録は、タスクディレクトリの親の外にある専用ディレクトリに残る。

```
~/.local/state/herdr-supervisor/
  ├─ AGENTS.md        supervisor が読むべき手順書。セッション開始時に読み込まれる
  ├─ CLAUDE.md        AGENTS.md を @ で読み込むだけ
  ├─ BOARD.md         全タスクの一覧（聞かれるたびに作り直す）
  ├─ RELATIONS.md     タスク横断の依存・衝突・申し送り（関係が変わるたびに上書き）
  └─ LOG.md           介入・起動・関係の発見と解消（追記のみ）
```

- coordinator の cwd は常にタスクディレクトリであり、**coordinator は実装しない。**
  対象が 1 リポジトリでも、それが呼び出し元のリポジトリでも、必ず worker tab を作る。
- 複数リポジトリでも workspace は増やさず、リポジトリ別 tab としてまとめる。
- coordinator と worker は別プロセスであり、会話文脈は引き継がれない。渡せるのはファイルのパスだけである。
  そのためタスク仕様書 `TASK.md` の質がそのままタスクの成否を左右する。
- 完遂の定義は「実装 + テスト通過 + コミット + push + PR」まで。PR は作業単位ごとに、
  それを担当した worker が出す。マージはユーザーの承認を得てから行う。
- coordinator は worker の完了報告を鵜呑みにせず、`git log` / `git diff` とテストの再実行で自ら検証する。
- coordinator の会話文脈が失われても、タスクディレクトリの記録から再開できる。worker への指示も
  ファイルに残るため、再開に呼び出し元の会話文脈は要らない。
- **記録への入口もタスクディレクトリに置く。** `AGENTS.md` と、それを読み込むだけの `CLAUDE.md` を
  置いてあるため、セッションをクリアされた coordinator と worker は、次のセッションの開始時に
  自分で役割を確かめて手順書へ戻る。worker の worktree もこのディレクトリの下にある。
- 記録は **変更頻度で分けてある。** 再開時に必ず読むのは TASK.md と STATE.md の 2 つで、
  伸び続ける PROGRESS.md は必要なときだけ日付で引く。
- 記録は決定に覆されて古くなる。**覆した coordinator が、その場で記録を訂正する。**
  古い記述は消さず、いまの前提を TASK.md の「現在地」に書いて優先させる。
- **supervisor はタスクを進めない。** 実装せず、worker に触らず、coordinator の代わりに判断せず、
  マージしない。各タスクの状態の正は `STATE.md` にあり、supervisor の一覧はそこから毎回作り直す。
  supervisor が正を持つのは、どのタスクにも置き場の無いタスク横断の関係だけである。

## インストール

```bash
ghq get github.com/yuanying/herdr-tasks
cd "$(ghq root)/github.com/yuanying/herdr-tasks"
./scripts/install-skill.sh
```

`~/.agents/skills` と `~/.claude/skills` に 2 つのスキルの symlink を張る。
`herdr-tasks` はこのリポジトリ、`herdr-supervisor` は同梱の `skills/herdr-supervisor/` を指す。
既にある場合は何もしない。別の実体が置かれている場合は、何も変更せずに中止する。

## 使い方

Coding Agent に `herdr-tasks` スキルを使うよう伝える。以降はスキルが、タスク名の決定から
仕様書の作成、対象リポジトリの特定、workspace の作成、coordinator の起動までを行う。

起動後、進捗は coordinator が持つ。様子を見るときは coordinator の pane を覗く。

```bash
herdr agent list
herdr agent attach <coordinator の agent 名>
```

全タスクをまとめて見たいときは「supervisor を起動して」と伝える（`herdr-supervisor` スキル）。
すでに起動していれば、その workspace を教えてくれる。以降は supervisor に「いまの状況は？」と聞く。新しいタスクも supervisor に頼めば、
タスク横断の関係を洗ったうえで起動する。

```bash
herdr agent attach supervisor
```

## 構成

| ファイル | 内容 |
|---|---|
| `SKILL.md` | 呼び出し元の手順と全体像、命名規則 |
| `coordinator.md` | coordinator が読む手順書 |
| `worker.md` | worker が読む手順書 |
| `supervisor.md` | supervisor が読む手順書 |
| `skills/herdr-supervisor/SKILL.md` | supervisor を起動する別スキル。起動済みならその workspace を案内する |
| `scripts/install-skill.sh` | `herdr-tasks` と `herdr-supervisor` の symlink を張る |
| `scripts/prompt-agent.sh` | agent の入力待ちとプロンプト着弾を判定する |
| `scripts/write-task-agents.sh` | タスクディレクトリに `AGENTS.md` / `CLAUDE.md` を生成する |
| `scripts/write-supervisor-agents.sh` | supervisor ディレクトリに `AGENTS.md` / `CLAUDE.md` を生成する |
| `scripts/lib/agents-entry.sh` | 2 つの入口生成が共有する処理 |
| `scripts/test-*.sh` | スクリプトのテスト |
| `templates/task-agents.md` | タスクディレクトリに生成される `AGENTS.md` の雛形 |
| `templates/supervisor-agents.md` | supervisor ディレクトリに生成される `AGENTS.md` の雛形 |
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
| supervisor | workspace `herdr-supervisor` / agent `supervisor` / `~/.local/state/herdr-supervisor/` |

詳細は [`SKILL.md`](SKILL.md) を参照。設計の背景と判断の理由は
[`docs/adr/0001-herdr-tasks-skill-architecture.md`](docs/adr/0001-herdr-tasks-skill-architecture.md) にある。
supervisor については [`docs/adr/0006-supervisor-across-tasks.md`](docs/adr/0006-supervisor-across-tasks.md) を参照。
