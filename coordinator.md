# coordinator 手順書

あなたはこのタスクの **coordinator** である。タスクが完遂されるまでの責任を持つ。
完遂とは「実装 + テスト通過 + コミット」まで。push と PR 作成は行わない。

あなたの会話文脈はいつ失われてもおかしくない。判断と状態はすべてタスクディレクトリの
ファイルに残し、記憶に依存しない。書いていないことは、次のあなたには存在しない。

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

## 1. 新規開始か再開かを判定する

タスクディレクトリは固定パスに残るため、あなたは中断されたタスクを引き継いでいる可能性がある。
**何かを作る前に必ずここを通る。** 記録と実体を突き合わせる。

```bash
cat PROGRESS.md
ls worktrees/ 2>/dev/null
herdr agent list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
```

`worktrees/` に実体があれば、それぞれで branch と作業状態を確認する。

```bash
git -C worktrees/<リポジトリ名> status -sb
git -C worktrees/<リポジトリ名> log --oneline -5
```

PROGRESS.md が空で、`worktrees/` に実体がなく、このタスクの worker agent もいなければ新規開始である。
手順 2 へ進む。いずれか 1 つでも存在すれば再開として扱い、リポジトリごとに次を分類する。

| 記録 | worktree | worker agent | 対処 |
|---|---|---|---|
| あり | あり | 生存 | 再接続する。`agent read` で現況を読み、必要なら追加指示を返す |
| あり | あり | 無し | 同じ worktree に worker を立て直す。指示ファイルをそのまま再利用する |
| あり | 無し | 無し | 未着手として扱い、手順 6 で作る |
| 無し | あり | — | 記録前に停止した痕跡。中身を確認して PROGRESS.md に取り込む |

**記録にない実体を勝手に消さない。** 自分が作ったと確認できないもの、中身の説明がつかないものは
ユーザーに確認する。

worker を立て直す前に、**その worktree の現状を手順 8 の方法で検証する**。コミットは git に残るため、
報告を受け取れなかっただけで作業が完了していることがある。終わっている作業をやり直させない。

PROGRESS.md に「要判断」の行があれば、ユーザーへの問い合わせが未解決のまま中断した可能性が高い。
記録された質問内容を読み、まだ回答がないなら手順 7 のエスカレーションからやり直す。

突き合わせの結果と、再開した事実を PROGRESS.md に書いてから先へ進む。

## 2. タスクを把握する

`TASK.md` を最後まで読む。ゴール・対象リポジトリ・依存関係・制約・完了条件・実行環境を自分の言葉で
言い直せる状態にする。仕様に致命的な欠落があり、どう仮定しても成果が無意味になる場合だけ、
ユーザーに問い合わせる（→ 「7. 監視とエスカレーション」）。それ以外は仮定を `PROGRESS.md` に
明記して進める。

「実行環境」に書かれたスキルのパス・agent kind・workspace ID は、worker の起動と立て直しに使う。
記述が欠けている場合は、いま分かる値を自分で調べて TASK.md に補う。

## 3. 進捗表を作る

`PROGRESS.md` に、対象リポジトリごとの状態表を作る。記録すべき項目は次のとおり。

- リポジトリ
- worktree のパス
- tab ID
- ブランチ
- base コミット（worktree を作った時点の SHA。検証時の比較起点になる）
- 担当 worker 名
- agent kind
- 状態（未着手・作業中・検証中・完了・要判断）
- 差し戻し回数
- 直近の出来事

**状態表は write-ahead で更新する。** worktree・tab・agent を作る *前* に行を書き、
作成後に応答から得た ID を埋める。途中で停止しても、手順 1 で「記録はあるが実体がない」
「実体はあるが記録がない」のどちらかとして必ず検出できる。作った後にまとめて書かない。

判断の経緯や調査で分かったことは `notes/` に書く。これは後からユーザーが読む記録であり、
中断した自分への引き継ぎでもある。

## 4. 作業対象を確定する

TASK.md の「対象リポジトリ」を正とする。「調査対象」と書かれた部分だけ、自分で確定させる。

```bash
ghq list --full-path
```

候補リポジトリの中を実際に検索し、変更が必要だと確認できたものだけを対象に加える。
追加・除外したら TASK.md に追記して理由を残す。

## 5. 実行体制を決める

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

## 6. worker を起動する

リポジトリごとに `git worktree` を作り、タスク workspace にその cwd の tab を追加して、
tab の root pane に agent を立てる。`herdr worktree create` は新しい workspace を作るため
worker には使わない。

作る前に PROGRESS.md へ行を追加する（手順 3 の write-ahead）。

```bash
git -C "$REPO_PATH" fetch origin        # remote がある場合
BASE_SHA="$(git -C "$REPO_PATH" rev-parse <デフォルトブランチの最新>)"
WORKTREE_PATH="$TASK_DIR/worktrees/$REPO_NAME"
mkdir -p "$TASK_DIR/worktrees"
git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE_PATH" "$BASE_SHA"
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$WORKTREE_PATH" \
  --label "$REPO_NAME" --no-focus
herdr agent start "$WORKER_NAME" --kind "$KIND" --pane <tab create 応答の .result.root_pane.pane_id>
```

- `BASE_SHA` は必ず PROGRESS.md に記録する。「デフォルトブランチの最新」は時間で動くため、
  記録しないと後から同じ差分を再現できない。
- ブランチ名・tab ラベル・agent 名の規則は `SKILL.md` の命名規則に従う。
- `--kind` は TASK.md の「実行環境」に記録された kind を使う。TASK.md に指定があればそれに従う。
- `tab_id` と `root_pane.pane_id` は `tab create` の応答 JSON から読む。推測しない。得た ID は
  すぐ PROGRESS.md の該当行に埋める。
- 同名リポジトリは worktree path と tab ラベルが衝突しないよう owner などを加える。
- 再開時に worktree が既に存在する場合は、パス・branch・対象 repository が一致することを
  確認して再利用する。branch だけが既に存在する場合は、その履歴がタスクの意図と一致することを
  確認して `-b` なしで worktree に追加する。重複作成や既存 branch の上書きはしない。

### 指示ファイルを書いてから渡す

worker への指示は **プロンプトに直接書かず**、先にファイルへ書く。会話文脈は失われるが、
ファイルは残る。差し戻し・再送・worker の立て直しは、すべてこのファイルを起点にする。

`$TASK_DIR/notes/workers/$WORKER_NAME.md` に次を書く。

- 担当リポジトリと worktree のパス、ブランチ、base コミット
- **担当範囲** — 何をどこまでやるか。触ってはいけない箇所。
- 依存と前提 — 他リポジトリで確定した契約、先に完了している作業
- 完了条件 — TASK.md のどのテストコマンドを通せばよいか
- 差し戻しの履歴 — 差し戻すたびに理由と指示を追記する

担当範囲は具体的に書く。worker は他リポジトリの状況を知らない。

### プロンプトを送る

起動したら worker に指示ファイルのパスを渡す。**`--wait` は付けない**。全 worker を起動してから
待つことで並列化する。

**`herdr agent start` の直後に prompt を投げるとテキストが消えることがある。**
送信前後の判定を共通化したスクリプトを使う。Codex の初回起動では、session ID が最初の入力後に
生成される場合や、directory trust 確認で止まる場合もこのスクリプトが検出する。

```bash
<スキルのパス>/scripts/prompt-agent.sh "$WORKER_NAME" \
  "あなたはこのタスクの worker です。まず <スキルのパス>/worker.md を読み、次に <タスクディレクトリ>/notes/workers/<worker 名>.md を読んでください。そこにあなたの担当範囲が書かれています。続けて <タスクディレクトリ>/TASK.md を読み、完了したら報告してください。"
```

exit 2 の場合は `SKILL.md` の trust 確認手順に従い、agent の cwd が今作成した worker worktree と
一致する場合だけ承認して、同じコマンドを再実行する。

worker が起動したのに一向に動き出さない場合、まず疑うのはプロンプトの消失である。
`herdr agent read "$WORKER_NAME" --source recent` で terminal を確認する。スクリプトは重複送信を
避けるため自動再送しないので、agent が処理していないことを確認できた場合だけ手動で再送する。

## 7. 監視とエスカレーション

起動後は各 worker の状態を追う。

```bash
herdr agent list
herdr agent wait "$WORKER_NAME" --timeout <ms>
herdr agent read "$WORKER_NAME" --source recent-unwrapped --lines 120
```

- `blocked` は承認待ちや質問。`agent read` で内容を読み、判断できるなら追加指示を prompt で返す。
  範囲や前提に関わる指示は、指示ファイルにも追記してから返す。
- 応答が代替画面に隠れて読み取れない場合は、worker に「回答を一時ファイルに書いてパスだけ返せ」と
  指示し、そのファイルを読む。
- 自力での解消を **2 回** 試し、それでも進まないならユーザーにエスカレーションする。
  他リポジトリの作業は止めずに継続する。

エスカレーションは通知と自分の pane への出力の両方で行う。

```bash
herdr notification show "<タスク名>: 判断が必要です" --body "<何に詰まっているか>" --sound request
```

**通知を出す前に、PROGRESS.md の該当行を「要判断」にし、何を聞いているかを書く。**
待っている間に自分が停止する可能性がある。記録がなければ、次のあなたは同じ質問を二重に投げるか、
回答待ちのまま放置する。

ユーザーが見に来たときに状況が分かるよう、詰まっている点・試したこと・選択肢を pane に出力してから待つ。
回答を得たら、内容と決定を PROGRESS.md か `notes/` に残してから作業を再開する。

## 8. 検証する（報告を信じない）

worker の完了報告は受け取るが、**成果の真偽は自分で確かめる**。リポジトリごとに以下を行う。

- `git -C <worktree> log --oneline` でコミットが実在することを確認する。
- `git -C <worktree> diff <base コミット>...HEAD --stat` と本文で、変更が担当範囲に収まっているか
  確認する。base は PROGRESS.md に記録した SHA を使う。
- `git -C <worktree> status --short` で未コミットの変更が残っていないか確認する。
- TASK.md の完了条件のテストコマンドを **自分で実行** して通ることを確認する。

不足があれば worker に差し戻す（worker が終了している場合は同じ worktree で立て直す）。
差し戻す理由と指示は指示ファイルに追記し、差し戻し回数を PROGRESS.md で数える。

## 9. リポジトリ間の整合を取る

複数リポジトリの場合、個別に通っても組み合わせが壊れていることがある。契約が両側で一致しているか、
呼び出し側と実装側のテストが互いの前提を満たしているかを確認する。ずれていれば該当 worker に修正させる。

## 10. 完遂報告

すべての検証が通ったら PROGRESS.md を完了状態に更新し、自分の pane に以下をまとめて出力する。

- リポジトリごとの: ブランチ名 / worktree パス / コミット（hash と subject）/ 実行したテストと結果
- タスク全体で満たしたゴールと、満たせなかった点
- 残課題・申し送り
- push と PR は行っていない旨

pane の出力は自分が停止すると読めなくなる。同じ内容を PROGRESS.md にも残す。

## 11. 片付け

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
