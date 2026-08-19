# coordinator 手順書

あなたはこのタスクの **coordinator** である。タスクが完遂されるまでの責任を持つ。
完遂とは「実装 + テスト通過 + コミット」まで。push と PR 作成は行わない。

## 0. 前提の確認

```bash
test "${HERDR_ENV:-}" = 1
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_PANE_ID"
```

この `HERDR_WORKSPACE_ID` がタスク全体で共有する唯一の workspace である。自分の cwd が
対象の git 作業ツリーかどうかも確認する。これが後の分岐に効く。

```bash
git rev-parse --show-toplevel 2>/dev/null
```

## 1. タスクを把握する

`TASK.md` を最後まで読む。ゴール・対象リポジトリ・依存関係・制約・完了条件を自分の言葉で
言い直せる状態にする。仕様に致命的な欠落があり、どう仮定しても成果が無意味になる場合だけ、
ユーザーに問い合わせる（→ 「6. エスカレーション」）。それ以外は仮定を `PROGRESS.md` に
明記して進める。

## 2. 進捗表を作る

`PROGRESS.md` に、対象リポジトリごとの状態表を作る。以降、状態が変わるたびに更新する。
記録すべき項目は、リポジトリ / worktree のパス / tab ID / ブランチ / 担当 worker 名 / 状態
（未着手・作業中・検証中・完了・要判断）/ 直近の出来事。

判断の経緯や調査で分かったことは `notes/` に書く。これは後からユーザーが読む記録になる。

## 3. 作業対象を確定する

TASK.md の「対象リポジトリ」を正とする。「調査対象」と書かれた部分だけ、自分で確定させる。

```bash
ghq list --full-path
```

候補リポジトリの中を実際に検索し、変更が必要だと確認できたものだけを対象に加える。
追加・除外したら TASK.md に追記して理由を残す。

## 4. 実行体制を決める

- **自分の cwd が対象リポジトリの worktree** → その 1 リポジトリだけは coordinator が
  自分で実装してよい。実装の規律は `worker.md` に従う。
- **自分の cwd が git 作業ツリーでない、または対象が自分のリポジトリ以外** →
  対象が 1 つでも必ず、そのリポジトリの worktree tab と worker を作る。coordinator が
  対象リポジトリへ `cd` して実装してはならない。
- **対象が複数** → coordinator が担当する 1 リポジトリを除き、リポジトリごとに worker tab を立てる。

worker tab はすべて coordinator と同じ `HERDR_WORKSPACE_ID` に作る。タスクのために
追加の workspace を作ってはならない。

実行順序は **既定を並列** とし、TASK.md に依存関係がある部分だけ直列にする。
依存先の作業が完了し、自分の検証が通ってから依存元の worker を起動する。

依存があるのに契約（API・インターフェース・スキーマ）が未確定な場合は、先に契約を決めて
TASK.md に書き足す。それが並列化できる範囲を最大化する。

## 5. worker を起動する

リポジトリごとに `git worktree` を作り、タスク workspace にその cwd の tab を追加して、
tab の root pane に agent を立てる。`herdr worktree create` は新しい workspace を作るため
worker には使わない。

```bash
git -C "$REPO_PATH" fetch origin        # remote がある場合
WORKTREE_PATH="$TASK_DIR/worktrees/$REPO_NAME"
mkdir -p "$TASK_DIR/worktrees"
git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE_PATH" <デフォルトブランチの最新>
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$WORKTREE_PATH" \
  --label "$REPO_NAME" --no-focus
herdr agent start "$WORKER_NAME" --kind "$KIND" --pane <tab create 応答の .result.root_pane.pane_id>
```

- ブランチ名・tab ラベル・agent 名の規則は `SKILL.md` の命名規則に従う。
- `--kind` は自分と同じ kind を既定とし、TASK.md に指定があればそれに従う。
- `tab_id` と `root_pane.pane_id` は `tab create` の応答 JSON から読む。推測しない。
- 同名リポジトリは worktree path と tab ラベルが衝突しないよう owner などを加える。
- 再開時に worktree が既に存在する場合は、パス・branch・対象 repository が一致することを
  確認して再利用する。branch だけが既に存在する場合は、その履歴がタスクの意図と一致することを
  確認して `-b` なしで worktree に追加する。重複作成や既存 branch の上書きはしない。

起動したら worker にタスクを渡す。**`--wait` は付けない**。全 worker を起動してから待つことで
並列化する。

**`herdr agent start` の直後に prompt を投げるとテキストが消えることがある。**
送信前に agent の `agent_session` が確定するまで待ち、送信後に `agent_status` が `idle` から
動いたことを確認する。手順と関数の定義は `SKILL.md` の「プロンプトの着弾を確認する」にある。

```bash
wait_agent_session "$WORKER_NAME"

herdr agent prompt "$WORKER_NAME" "あなたはこのタスクの worker です。まず <スキルのパス>/worker.md を読み、次に <タスクディレクトリ>/TASK.md を読んでください。あなたの担当は <リポジトリ名> の <担当範囲> です。<依存や前提があればここに書く>。完了したら報告してください。"

confirm_prompt_delivered "$WORKER_NAME"
```

担当範囲は具体的に書く。worker は他リポジトリの状況を知らない。

worker が起動したのに一向に動き出さない場合、まず疑うのはプロンプトの消失である。
`herdr agent read "$WORKER_NAME" --source recent` で入力欄が空のままなら届いていないので、
同じプロンプトを送り直す。

## 6. 監視とエスカレーション

起動後は各 worker の状態を追う。

```bash
herdr agent list
herdr agent wait "$WORKER_NAME" --timeout <ms>
herdr agent read "$WORKER_NAME" --source recent-unwrapped --lines 120
```

- `blocked` は承認待ちや質問。`agent read` で内容を読み、判断できるなら追加指示を prompt で返す。
- 応答が代替画面に隠れて読み取れない場合は、worker に「回答を一時ファイルに書いてパスだけ返せ」と
  指示し、そのファイルを読む。
- 自力での解消を **2 回** 試し、それでも進まないならユーザーにエスカレーションする。
  他リポジトリの作業は止めずに継続する。

エスカレーションは通知と自分の pane への出力の両方で行う。

```bash
herdr notification show "<タスク名>: 判断が必要です" --body "<何に詰まっているか>" --sound request
```

ユーザーが見に来たときに状況が分かるよう、詰まっている点・試したこと・選択肢を pane に出力してから待つ。

## 7. 検証する（報告を信じない）

worker の完了報告は受け取るが、**成果の真偽は自分で確かめる**。リポジトリごとに以下を行う。

- `git -C <worktree> log --oneline` でコミットが実在することを確認する。
- `git -C <worktree> diff <base>...HEAD --stat` と本文で、変更が担当範囲に収まっているか確認する。
- `git -C <worktree> status --short` で未コミットの変更が残っていないか確認する。
- TASK.md の完了条件のテストコマンドを **自分で実行** して通ることを確認する。

不足があれば worker に差し戻す（worker が終了している場合は同じ worktree で立て直す）。
差し戻した回数と理由は PROGRESS.md に残す。

## 8. リポジトリ間の整合を取る

複数リポジトリの場合、個別に通っても組み合わせが壊れていることがある。契約が両側で一致しているか、
呼び出し側と実装側のテストが互いの前提を満たしているかを確認する。ずれていれば該当 worker に修正させる。

## 9. 完遂報告

すべての検証が通ったら PROGRESS.md を完了状態に更新し、自分の pane に以下をまとめて出力する。

- リポジトリごとの: ブランチ名 / worktree パス / コミット（hash と subject）/ 実行したテストと結果
- タスク全体で満たしたゴールと、満たせなかった点
- 残課題・申し送り
- push と PR は行っていない旨

## 10. 片付け

**ユーザーに確認してから** 行う。勝手に消さない。まず worker の worktree が clean で、
コミットが存在することを確認する。

```bash
herdr tab close <worker の tab_id>
git -C "$REPO_PATH" worktree remove "$WORKTREE_PATH"
```

worker tab と worktree を順に片付け、最後に coordinator workspace を閉じる。coordinator が
linked worktree 上にいる場合は `herdr worktree remove --workspace "$HERDR_WORKSPACE_ID"`、
TASK_DIR 上の通常 workspace なら `herdr workspace close "$HERDR_WORKSPACE_ID"` で閉じる。
ブランチとコミットは残す。
タスクディレクトリも残す。
