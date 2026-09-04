# 0002. 1 タスクを 1 workspace とし、作業リポジトリを tab にまとめる

- Date: 2026-08-19
- Status: Accepted（coordinator の cwd に関する決定は
  [ADR 0005](0005-task-directory-entry-point.md) が改めている）

## Context

ADR 0001 では worker ごとに workspace を作る構成にしていた。しかし複数リポジトリの
worker workspace がサイドバーへ分散し、1 つのタスクとして追いにくい。また呼び出し元の
リポジトリと実際の作業対象が異なる場合でも、呼び出し元リポジトリの worktree が coordinator
workspace になり、タスクに無関係な branch と worktree を作っていた。

Herdr は任意の cwd を持つ tab を既存 workspace に追加できる。worker 用 worktree を
`git worktree` で作り、`herdr tab create --workspace` で開けば、リポジトリごとの独立した
作業環境を保ちながら 1 つの task workspace にまとめられる。

## Decision

- 1 タスクにつき workspace は 1 つだけ作る。
- coordinator は task workspace の root tab に置く。
- 呼び出し元リポジトリが対象リポジトリに含まれる場合だけ、その worktree を coordinator
  の cwd とし、coordinator が担当できる。
  （ADR 0005 で改定。coordinator の cwd は常に TASK_DIR とし、coordinator は実装しない）
- 呼び出し元が対象外の場合は TASK_DIR を coordinator の cwd とする。対象が 1 リポジトリでも、
  対象リポジトリの worktree tab と worker を必ず作る。
- worker worktree は `$TASK_DIR/worktrees/<リポジトリ名>` に作る。
- worker は `herdr tab create --workspace "$HERDR_WORKSPACE_ID"` で同じ workspace の
  リポジトリ別 tab に配置する。worker のために追加 workspace を作らない。
- coordinator は repository / worktree path / tab ID / branch / worker name を
  PROGRESS.md に記録し、worker を監視・検証する。
- 片付けはユーザー確認後に worker tab を閉じ、対応する git worktree を削除してから、
  coordinator workspace を最後に閉じる。

## Consequences

- Herdr 上で 1 タスクの coordinator と全 worker を 1 workspace として追える。
- 呼び出し元と作業対象が異なる単一リポジトリ案件でも、実装は必ず対象リポジトリの worker が行う。
- worker worktree の作成と削除は Herdr の workspace 単位の worktree helper ではなく、
  `git worktree` と tab lifecycle を組み合わせて管理する必要がある。
- worker tab の ID と worktree path を記録しないと安全に再開・片付けできないため、
  PROGRESS.md の状態管理が重要になる。
