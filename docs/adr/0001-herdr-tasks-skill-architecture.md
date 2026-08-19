# 0001. herdr-tasks スキルのアーキテクチャ

- Date: 2026-08-19
- Status: Superseded by [ADR 0002](0002-task-workspace-with-repository-tabs.md)

## Context

タスクを与えられたときに、herdr の workspace / worktree を使ってタスクを完遂するためのスキルが欲しい。前提と制約は以下の通り。

- herdr は `herdr worktree create` で「worktree を切り、それを新規 workspace として開く」。つまり **1 worktree = 1 workspace** である。
- herdr の pane で起動された Coding Agent は別プロセスであり、起動元の会話文脈を自動では引き継がない。
- Claude Code の fork サブエージェントは同一プロセス内で動くため、herdr の pane / workspace には配置できない。
- herdr の agent 名は `[a-z][a-z0-9_-]{0,31}` の制約を持ち、`#` を含められない。
- Claude をはじめとする多くの Coding Agent は代替画面（alternate screen）を使うため、`herdr agent read` では長い応答を完全に取得できないことがある。
- タスクは単一リポジトリで完結するとは限らず、`ghq list` で管理された複数リポジトリにまたがることがある。
- スキルは Claude 以外の Coding Agent からも利用できる形にしたい。

これらの上で、誰がタスク完遂の責任を持ち、どこで作業し、どう名前を付け、どこまでを自動で行うかを決める必要がある。

## Decision

### 役割構成

- タスク完遂に責任を持つ **coordinator** を、新規 workspace 上に別プロセスの Coding Agent として起動する。
- 呼び出し元セッションはタスク仕様書を書き、coordinator を起動し、起動報告をして手を引く。フォーカスは移さない。
- 対象が coordinator のいるリポジトリ 1 つだけの場合は coordinator が自分で修正する。それ以外の場合はリポジトリごとに **worker** を立てる。

### 配置と文脈の受け渡し

- タスク仕様書と進捗は `~/.local/state/herdr-tasks/<タスク名>/` に置き、`TASK.md`（背景・ゴール・制約・対象リポジトリ・依存関係・完了条件）と `PROGRESS.md`、`notes/` で構成する。
- 呼び出し元は仕様書を書いた上で、そのパスと役割手順書のパスを prompt で coordinator に渡す。
- coordinator workspace の cwd は、呼び出し元が git リポジトリ内なら**そのリポジトリの worktree**、リポジトリ外なら**呼び出し元ディレクトリ**とする。

### 命名

- タスク名は issue 関連なら `#<issue番号>-<slug>`、それ以外は `<slug>`。workspace ラベルとタスクディレクトリ名に用いる。
- ブランチ名は `issue-<issue番号>-<slug>`（issue なしは `<slug>`）とし、`#` を含めない。
- agent 名はタスク名から機械的に短縮し、herdr の制約に収める。

### 進行と検証

- 対象リポジトリは `ghq list` で特定し、**タスク仕様書に明記**する。coordinator はそれに従い、作業中に判明した追加分のみ自ら追加する。
- 実行順序は既定を並列とし、リポジトリ間に依存がある部分だけ直列にする。
- 完了条件は「実装 + テスト通過 + コミットまで」。push と PR 作成は含めない。
- worker は完了報告を行うが、coordinator は git log / diff / テスト再実行によって自ら検証する。
- worker が承認待ちやエラーで停止した場合、coordinator がまず自力で対処し、解消できない場合にユーザーへエスカレーションする。
- 完了後の worktree / workspace の片付けは、ユーザーに確認してから行う。

### 実装形態

- agent kind の既定は呼び出し元と同じ kind（`herdr agent list` で判定）とし、指示によって変更できる。
- スキルは `~/src/github.com/yuanying/herdr-tasks` で git 管理し、`~/.claude/skills/herdr-tasks` から symlink する。
- リポジトリ直下に `SKILL.md`（呼び出し元の手順と全体像）、`coordinator.md`、`worker.md` を置き、ベンダー中立な記述とする。

## Consequences

- 呼び出し元セッションは長時間拘束されず、別作業に使える。一方で進捗はユーザーが coordinator の workspace を見に行かないと分からない。
- 会話文脈が自動継承されないため、タスク仕様書の質がそのままタスクの成否を左右する。仕様書が薄いと coordinator は意図を復元できない。
- タスクディレクトリが予測可能な固定パスにあるため、coordinator が停止しても同じ場所から再開できる。反面、明示的に削除しない限り残り続ける。
- 単一リポジトリ案件では余分なプロセスが立たず軽い。複数リポジトリでは worker 数だけ workspace が増えるため、herdr の画面が賑やかになる。
- workspace ラベルとブランチ名で表記が分かれるため、対応関係をスキル側で機械的に導出する必要がある。
- coordinator が worker の報告を鵜呑みにせず検証するぶん、coordinator の作業量は増えるが、未完了のまま完了扱いされる事故を防げる。
- push と PR を含めないため、成果を外部に出す判断は必ず人が行う。その代わり、完遂後に人の操作が一手間残る。
- 呼び出し元が git リポジトリ外にいる場合、coordinator の cwd はリポジトリではなくなるため、単一リポジトリ案件でも worker 相当の worktree を別途作る経路が必要になる。
