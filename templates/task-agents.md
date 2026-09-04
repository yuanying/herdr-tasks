<!-- herdr-tasks generated file. 手で書き換えない。書き換えは templates/task-agents.md 側で行う -->

# herdr-tasks のタスクディレクトリ

- `$TASK_DIR` = `@@TASK_DIR@@` — このタスクの記録置き場
- `$SKILL_DIR` = `@@SKILL_DIR@@` — 手順書の置き場

あなたはこのタスクのために立てられた agent であり、**会話文脈を失った状態でこれを
読んでいるかもしれない。** 手順書を読んだ覚えが無ければ、何かを始める前に読む。
役割は cwd で決まる。

| cwd | 役割 | 読むもの |
|---|---|---|
| `$TASK_DIR` | coordinator | `$SKILL_DIR/coordinator.md` → `$TASK_DIR/TASK.md` → `$TASK_DIR/STATE.md` |
| `$TASK_DIR/worktrees/<作業単位>` | worker | `$SKILL_DIR/worker.md` → `$TASK_DIR/notes/workers/<worker 名>.md` |

自分の worker 名が分からなければ、`$TASK_DIR/STATE.md` の状態表から
**自分の cwd と一致する worktree の行** を引く。
