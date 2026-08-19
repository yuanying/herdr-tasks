---
name: herdr-tasks
description: >-
  herdr の workspace / worktree を使って、与えられたタスクを完遂まで面倒を見る。
  トリガー: "herdr-tasks", "/herdr-tasks", "herdr でタスクを進めて",
  "このタスクを別 workspace でやって"。使用場面: (1) 独立したタスクを専用
  workspace に切り出したい、(2) 複数リポジトリにまたがる修正、
  (3) 時間のかかる実装を別セッションに任せて手元を空けたい
---

# herdr-tasks

タスクを受け取ったら、herdr 上に **1 タスク = 1 workspace** の専用 workspace を作り、
root tab に常駐する **coordinator** にタスク完遂までの責任を持たせる。作業対象ごとに
同じ workspace 内へリポジトリ別の worktree tab を作って **worker** を立て、
coordinator がそれらを取りまとめる。

このスキルは特定の Coding Agent に依存しない。`herdr` CLI と `git`、`ghq` があれば動く。

## 役割

| 役割 | 居場所 | 責任 |
|---|---|---|
| 呼び出し元 | 現在の pane | タスク仕様書を書き、coordinator を起動し、起動報告をして手を引く |
| coordinator | タスク専用 workspace の root tab | タスク完遂までの責任。worker の起動・監視・検証・取りまとめ |
| worker | 同じ workspace 内のリポジトリ別 worktree tab | 担当リポジトリの実装・テスト・コミット |

- 呼び出し元のリポジトリが対象リポジトリに含まれる場合だけ、coordinator は自分の worktree を担当できる。
- 呼び出し元と作業対象のリポジトリが異なる場合は、対象が 1 つでも必ず対象リポジトリの
  worktree tab と worker を作る。
- 対象が複数の場合も workspace は増やさず、同じタスク workspace にリポジトリ別 tab を追加する。
- coordinator と worker は別プロセスであり、会話文脈は引き継がれない。渡せるのは **ファイルのパス** だけである。

## 前提条件

```bash
test "${HERDR_ENV:-}" = 1
```

これが失敗する場合は herdr の中にいない。その旨を伝えて中止する。

## 命名規則

タスク名を 1 つ決め、そこからすべてを導出する。

| 用途 | 形式 | 例 |
|---|---|---|
| タスク名（issue 関連） | `#<issue番号>-<slug>` | `#42-add-retry-to-uploader` |
| タスク名（その他） | `<slug>` | `add-retry-to-uploader` |
| coordinator workspace ラベル | タスク名 | `#42-add-retry-to-uploader` |
| worker tab ラベル | `<リポジトリ名>` | `herdr` |
| ブランチ名 | `issue-<issue番号>-<slug>` / `<slug>` | `issue-42-add-retry-to-uploader` |
| タスクディレクトリ | `~/.local/state/herdr-tasks/<タスク名>/` | |
| coordinator agent 名 | `coord-` + 短縮 | `coord-42-add-retry` |
| worker agent 名 | `work-` + 短縮 + `-` + リポジトリ名 | `work-42-herdr` |

- slug は英小文字・数字・ハイフンで、タスク内容が読み取れる 3〜5 語程度にする。
- ブランチ名に `#` は使わない。ディレクトリ名と workspace ラベルには使う（シェルでは必ずクォートする）。
- worker worktree は `$TASK_DIR/worktrees/<リポジトリ名>` に置く。同名リポジトリがある場合は
  owner などを加えて task 内で一意にする。
- agent 名は herdr の制約 `[a-z][a-z0-9_-]{0,31}` に収める。`#` を除去し、31 文字を超えるなら
  slug 側を削る。リポジトリ名は削らない。`herdr agent list` で既存名と衝突しないことを確認し、
  衝突したら末尾に `-2` を付ける。

## 呼び出し元の手順

### 1. タスク名とブランチ名を決める

issue 由来かどうかを判断し、上の命名規則に従って `TASK_NAME` と `BRANCH` を決める。
判断に迷うほど内容が曖昧な場合は、ここでユーザーに一度確認する。

### 2. タスクディレクトリと仕様書を作る

```bash
TASK_DIR="$HOME/.local/state/herdr-tasks/$TASK_NAME"
mkdir -p "$TASK_DIR/notes"
```

`$TASK_DIR/TASK.md` に以下を書く。**coordinator が受け取れる文脈はこのファイルだけ**なので、
会話の中で決まったことを省略せずに書き切る。

- **タスク名 / ブランチ名**
- **背景** — なぜこれをやるのか。会話で共有された前提。
- **ゴール** — 完了時に何が成立していれば良いか。
- **対象リポジトリ** — `ghq` のフルパスと、それぞれの担当範囲。未確定なら「調査対象」と明記する。
- **リポジトリ間の依存関係** — どちらを先に確定させる必要があるか。無ければ「なし（並列可）」。
- **制約・方針** — 既存の設計方針、触ってはいけない箇所、踏襲すべき既存実装。
- **完了条件** — 通すべきテストコマンドを具体的に書く。
- **参考情報** — issue URL、関連ファイル、既存の議論、ADR。

`$TASK_DIR/PROGRESS.md` は空で作る（coordinator が更新する）。

### 3. 対象リポジトリを特定する

```bash
ghq list --full-path
```

タスクに関係しそうなリポジトリを絞り込み、必要なら中を検索して確証を得てから TASK.md に明記する。
ここで特定しきれない部分だけを「調査対象」として残す。

### 4. coordinator workspace を作る

手順 3 で確定した対象リポジトリと、呼び出し元のリポジトリを比較する。

**呼び出し元のリポジトリが対象に含まれる場合** — そのリポジトリの worktree を
coordinator の root tab にする。coordinator はこのリポジトリを担当できる。

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
git -C "$REPO_ROOT" fetch origin        # remote がある場合
herdr worktree create --cwd "$REPO_ROOT" --branch "$BRANCH" --base <デフォルトブランチの最新> \
  --label "$TASK_NAME" --no-focus
```

**呼び出し元がリポジトリ外、または呼び出し元のリポジトリが対象外の場合** —
無関係なリポジトリの worktree を作らず、タスクディレクトリを cwd とする coordinator
workspace を作る。この場合、対象が 1 リポジトリでも coordinator は実装せず worker tab を作る。

```bash
herdr workspace create --cwd "$TASK_DIR" --label "$TASK_NAME" --no-focus
```

いずれも応答 JSON から `.result.workspace.workspace_id` と `.result.root_pane.pane_id` を読む。
ID は応答から取る。推測しない。

### 5. agent kind を決める

既定は呼び出し元と同じ kind。`herdr agent list` の中から `pane_id` が `$HERDR_PANE_ID` の
エントリを探し、その `agent` を使う。ユーザーから指定があればそれを優先する。

### 6. coordinator を起動する

root pane はシェルプロンプトの状態にある。そこに agent を起動する。

```bash
herdr agent start "$COORD_NAME" --kind "$KIND" --pane "$ROOT_PANE"
```

### 7. タスクを渡す

`--wait` は付けない。投げたら戻る。

**送信前に agent がプロンプトを受け付けられる状態になるまで待つ。** 詳細は「プロンプトの着弾を確認する」を参照。

```bash
wait_agent_session "$COORD_NAME"

herdr agent prompt "$COORD_NAME" "あなたはこのタスクの coordinator です。まず <スキルのパス>/coordinator.md を読み、次に $TASK_DIR/TASK.md を読み、その手順に従ってタスクを完遂してください。"

confirm_prompt_delivered "$COORD_NAME"
```

`<スキルのパス>` はこの SKILL.md が置かれているディレクトリの絶対パスに置き換える。

### 8. 報告して終わる

フォーカスは移さない。ユーザーに以下を伝えて終了する。

- タスク名と workspace ラベル
- coordinator の agent 名（`herdr agent attach <名前>` で覗ける旨）
- タスクディレクトリのパス
- 対象リポジトリ（判明している分）
- すべての worker が同じ workspace のリポジトリ別 tab に作られる旨

以降の進捗は coordinator が持つ。呼び出し元はこのタスクを監視しない。

## プロンプトの着弾を確認する

**`herdr agent start` が `interactive_ready: true` を返しても、agent がプロンプトを受け付けられる
とは限らない。** 起動直後に `herdr agent prompt` を投げると、テキストがどこにも入らずに消えることが
ある。このとき `agent prompt` は `agent_prompted` を返して成功したように見えるため、投げっぱなしにすると
気づけない。coordinator を起動して沈黙する、worker が動き出さない、といった形で後から発覚する。

見分け方は `agent_session` の有無である。まだセッションが確定していない agent は応答に
`agent_session` を持たず、`agent_status` が `blocked`、`revision` が `0` になる。

| | 受け付けられない状態 | 受け付けられる状態 |
|---|---|---|
| `agent_session` | 無し | `{"kind":"id","value":"..."}` |
| `agent_status` | `blocked` | `idle` |
| `revision` | `0` | `1` 以上 |

そこで **送信前に待ち、送信後に確認する**。agent を起動してプロンプトを渡す箇所ではすべてこれを行う
（呼び出し元が coordinator に渡すとき、coordinator が worker に渡すときの両方）。

### 送信前: セッションが確定するまで待つ

```bash
wait_agent_session() {
  local name="$1" i
  for i in $(seq 1 60); do
    if herdr agent get "$name" 2>/dev/null \
       | jq -e '.result.agent.agent_session.value // empty' >/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "agent $name のセッションが確定しない" >&2
  return 1
}
```

### 送信後: 届いたことを確認する

送ったプロンプトが画面に現れたか、agent が動き出したかを見る。

```bash
confirm_prompt_delivered() {
  local name="$1" i
  for i in $(seq 1 30); do
    case "$(herdr agent get "$name" | jq -r '.result.agent.agent_status')" in
      working|blocked|done) return 0 ;;
    esac
    sleep 1
  done
  herdr agent read "$name" --source recent --lines 40
  echo "プロンプトが届いていない可能性がある。上の出力を確認して送り直すこと" >&2
  return 1
}
```

`agent_status` が `idle` のまま動かない場合は届いていない。**同じプロンプトをもう一度送ってよい**
（届いていないので重複にはならない）。それでも駄目なら `herdr agent read` で画面を直接見て、
入力欄にテキストが残っていないか、承認ダイアログなど別の画面に切り替わっていないかを確認する。

## coordinator が停止した場合の再開

タスクディレクトリは固定パスに残るため、同じ workspace の pane で agent を起動し直し、
`coordinator.md` と `TASK.md`、`PROGRESS.md` を読ませれば再開できる。

## ファイル

- `SKILL.md` — このファイル。呼び出し元の手順と全体像。
- `coordinator.md` — coordinator が読む手順書。
- `worker.md` — worker が読む手順書。
- `scripts/install-skill.sh` — `~/.agents/skills` と `~/.claude/skills` に symlink を張る。
- `docs/adr/` — 設計判断の記録。
