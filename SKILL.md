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

タスクが増えたら、全タスクを束ねる **supervisor** を 1 つだけ常駐させる
（→ 「supervisor を起動する」）。supervisor は聞かれたときに全タスクの一覧を作り、
タスクをまたぐ依存・衝突・申し送りを管理する。

このスキルは特定の Coding Agent に依存しない。`herdr` CLI と `git`、`ghq` があれば動く。

## 役割

| 役割 | 居場所 | 責任 |
|---|---|---|
| 呼び出し元 | 現在の pane | タスク仕様書を書き、coordinator を起動し、起動報告をして手を引く |
| coordinator | タスク専用 workspace の root tab（cwd はタスクディレクトリ） | タスク完遂までの責任。worker の起動・監視・検証・取りまとめ |
| worker | 同じ workspace 内の作業単位ごとの worktree tab | その作業単位の実装・テスト・コミット |
| supervisor | 専用 workspace `herdr-supervisor`（cwd は supervisor ディレクトリ） | 全タスクの一覧化とタスク横断の管理。新規タスクの起動（呼び出し元を担う）と介入（どちらもユーザー確認後） |

- **coordinator は実装しない。** 呼び出し元のリポジトリが対象に含まれていても、対象が 1 つでも、
  必ず対象リポジトリの worktree tab と worker を作る（→ ADR 0005）。
- 対象が複数の場合も workspace は増やさず、同じタスク workspace にリポジトリ別 tab を追加する。
- coordinator と worker は別プロセスであり、会話文脈は引き継がれない。渡せるのは **ファイルのパス** だけである。
- **手順書へ戻る道はタスクディレクトリの `AGENTS.md` / `CLAUDE.md` が持つ。** 会話文脈を失った
  agent が、次のセッションの開始時にそれを読んで自分で手順書へ戻る（→ ADR 0005）。
- **worker は 1 PR の単位で立てて、その単位が終わったら閉じる。** 使い回さない（→ ADR 0004）。
- **supervisor も実装しない。** worker には直接触らず、coordinator の代わりに判断せず、
  マージもしない。監視はユーザーに聞かれたときだけ行う（→ ADR 0006、`supervisor.md`）。

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
| worker tab ラベル | 作業単位のブランチ名 | `add-retry` |
| ブランチ名 | `issue-<issue番号>-<slug>` / `<slug>` | `issue-42-add-retry-to-uploader` |
| タスクディレクトリ | `~/.local/state/herdr-tasks/<タスク名>/` | |
| coordinator agent 名 | `coord-` + 短縮 | `coord-42-add-retry` |
| worker agent 名 | `work-` + 作業単位のブランチ名 | `work-add-retry` |
| supervisor workspace ラベル | 固定 | `herdr-supervisor` |
| supervisor agent 名 | 固定 | `supervisor` |
| supervisor ディレクトリ | `~/.local/state/herdr-supervisor/`（推奨） | |

- slug は英小文字・数字・ハイフンで、タスク内容が読み取れる 3〜5 語程度にする。
- ブランチ名に `#` は使わない。ディレクトリ名と workspace ラベルには使う（シェルでは必ずクォートする）。
- **worker まわりは「担当」ではなく「作業単位」で名付ける**（→ ADR 0004）。
  worker worktree は `$TASK_DIR/worktrees/<ブランチ名>` に置く。
  複数リポジトリにまたがるタスクでブランチ名が衝突する場合は、リポジトリ名を前に足す。
- agent 名は herdr の制約 `[a-z][a-z0-9_-]{0,31}` に収める。`#` を除去し、31 文字を超えるなら
  slug 側を削る。`herdr agent list` で既存名と衝突しないことを確認し、
  衝突したら末尾に `-2` を付ける。

## 呼び出し元の手順

### 1. タスク名とブランチ名を決める

issue 由来かどうかを判断し、上の命名規則に従って `TASK_NAME` と `BRANCH` を決める。
判断に迷うほど内容が曖昧な場合は、ここでユーザーに一度確認する。

### 2. タスクディレクトリと仕様書を作る

```bash
TASK_DIR="$HOME/.local/state/herdr-tasks/$TASK_NAME"
mkdir -p "$TASK_DIR/notes/workers"
```

`$TASK_DIR/TASK.md` に以下を書く。**coordinator が受け取れる文脈はこのファイルだけ**なので、
会話の中で決まったことを省略せずに書き切る。

- **タスク名 / ブランチ名**
- **現在地** — **空の節として最初に置く。** ここは coordinator が埋める場所であり、
  呼び出し元は枠と「この節が以下の本文より優先する」という一文だけを書く。
  タスクが進むと本文の前提は決定に覆される。**覆した coordinator がここを直す**
  （→ `coordinator.md`「記録を訂正する」）。枠が無いと、直す先が無いまま本文だけが古くなる。
- **背景** — なぜこれをやるのか。会話で共有された前提。
- **ゴール** — 完了時に何が成立していれば良いか。
- **対象リポジトリ** — `ghq` のフルパスと、それぞれの担当範囲。未確定なら「調査対象」と明記する。
- **リポジトリ間の依存関係** — どちらを先に確定させる必要があるか。無ければ「なし（並列可）」。
- **制約・方針** — 既存の設計方針、触ってはいけない箇所、踏襲すべき既存実装。
- **完了条件** — 通すべきテストコマンドを具体的に書く。
- **参考情報** — issue URL、関連ファイル、既存の議論、ADR。
- **実行環境** — このスキルが置かれているディレクトリの絶対パス。coordinator と worker が
  手順書を読むために使う。workspace ID と agent kind は手順 5 の後に追記する。

タスクディレクトリの記録は **変更頻度で 3 つに分かれている**（→ `coordinator.md` 手順 3）。
残る 2 つも、呼び出し元がここで用意する。

- `$TASK_DIR/STATE.md` — **枠だけ作る。** 1 行目に状態行 `状態: 進行中` を置き、
  続けて状態表の見出しと「次にやること」「未解決の要判断」の見出しを置き、中身は空にする。
  coordinator が毎回上書きする。
- `$TASK_DIR/PROGRESS.md` — 空で作る。日付つきの時系列で、coordinator が追記していく。

```markdown
状態: 進行中

# STATE

## 状態表

## 次にやること

## 未解決の要判断
```

**呼び出し元は状態行のほかに中身を書かない。** STATE.md の状態表が空であることが、
coordinator の新規開始判定の材料になる。状態行は、タスクの外から状態を機械的に読むための
1 行であり、以降は coordinator が更新する（→ `coordinator.md` 手順 3「状態行」）。
起動した直後から一覧に「進行中」として載せるため、最初の値は呼び出し元が入れる。

タスクディレクトリに残したものが、coordinator の会話文脈が失われたときの唯一の手掛かりになる。
会話でしか共有されていない前提は、ここで必ず書き出す。

記録を置いても、**それを読む理由が失われれば同じことである。** セッションをクリアした
coordinator や worker は、手順書のパスをプロンプトで受け取ったこと自体を忘れている。
タスクディレクトリに入口を置き、次のセッションの開始時に自動で読ませる。

```bash
<スキルのパス>/scripts/write-task-agents.sh "$TASK_DIR"
```

`$TASK_DIR/AGENTS.md`（役割の見分け方と読むべき手順書）と、それを `@` で読み込むだけの
`$TASK_DIR/CLAUDE.md` を生成する。worker の worktree はこのディレクトリの下に作るため、
同じファイルが worker にも届く。何度実行してもよい。手で書かれた同名ファイルは上書きしない。

### 3. 対象リポジトリを特定する

```bash
ghq list --full-path
```

タスクに関係しそうなリポジトリを絞り込み、必要なら中を検索して確証を得てから TASK.md に明記する。
ここで特定しきれない部分だけを「調査対象」として残す。

### 4. coordinator workspace を作る

**cwd は常にタスクディレクトリである。** 呼び出し元のリポジトリが対象に含まれていても、
そのリポジトリの worktree を coordinator の root tab にしない。coordinator は実装せず、
対象リポジトリは 1 つでも worker が担当する（→ ADR 0005）。

```bash
herdr workspace create --cwd "$TASK_DIR" --label "$TASK_NAME" --no-focus
```

応答 JSON から `.result.workspace.workspace_id` と `.result.root_pane.pane_id` を読む。
ID は応答から取る。推測しない。

### 5. agent kind を決める

既定は呼び出し元と同じ kind。`herdr agent list` の中から `pane_id` が `$HERDR_PANE_ID` の
エントリを探し、その `agent` を使う。ユーザーから指定があればそれを優先する。

決めた kind と、手順 4 の応答から得た workspace ID を TASK.md の「実行環境」に追記する。
coordinator が停止しても、この記述だけで worker を同じ kind・同じ workspace に立て直せる。

### 6. coordinator を起動する

root pane はシェルプロンプトの状態にある。そこに agent を起動する。

```bash
herdr agent start "$COORD_NAME" --kind "$KIND" --pane "$ROOT_PANE"
```

### 7. タスクを渡す

`--wait` は付けない。投げたら戻る。

**送信前に agent がプロンプトを受け付けられる状態になるまで待ち、送信後に着弾を確認する。**
手書きのポーリング処理を作らず、このスキルのスクリプトを使う。

```bash
<スキルのパス>/scripts/prompt-agent.sh "$COORD_NAME" \
  "あなたはこのタスクの coordinator です。まず <スキルのパス>/coordinator.md を読み、次に $TASK_DIR/TASK.md を読み、その手順に従ってタスクを完遂してください。"
```

`<スキルのパス>` はこの SKILL.md が置かれているディレクトリの絶対パスに置き換える。
スクリプトが exit 2 を返した場合は、後述の trust 確認を処理してから同じコマンドを再実行する。

### 8. 報告して終わる

フォーカスは移さない。ユーザーに以下を伝えて終了する。

- タスク名と workspace ラベル
- coordinator の agent 名（`herdr agent attach <名前>` で覗ける旨）
- タスクディレクトリのパス
- 対象リポジトリ（判明している分）
- すべての worker が同じ workspace のリポジトリ別 tab に作られる旨

以降の進捗は coordinator が持つ。呼び出し元はこのタスクを監視しない。
全タスクの様子をまとめて見たいときは、supervisor に聞く。

## supervisor を起動する

タスクが増えると、どれが走っていて、どれが判断待ちで、どれが止まっているかを一望できなくなる。
タスク同士の関係（あるタスクが別タスクの PR を待つ、複数のタスクが同じリポジトリを触る）を
置く場所も無い。各 coordinator は自分のタスクしか見ていないからである。
これを受け持つのが supervisor である（→ ADR 0006）。手順は `supervisor.md` にある。

**supervisor は全体で 1 つだけ立てる。** 起動を頼まれた agent が、次を行う。

### 1. 既に居ないか確かめる

```bash
herdr workspace list
herdr agent list
```

ラベル `herdr-supervisor` の workspace、または名前 `supervisor` の agent があれば、
新しく立てない。agent が生きていればそれを使う。workspace だけが残っていれば、
`herdr tab list --workspace <その workspace ID>` で root pane を読み、そこに手順 4 の
`herdr agent start` から起動し直す。

### 2. 専用ディレクトリを作る

```bash
SUPERVISOR_DIR="$HOME/.local/state/herdr-supervisor"
mkdir -p "$SUPERVISOR_DIR"
```

**タスクディレクトリの親（`~/.local/state/herdr-tasks/`）の中には作らない。** supervisor は
そこを走査して一覧を作るため、中に置くと自分自身がタスクとして混ざる。
既にディレクトリがあれば、前の supervisor の記録が残っている。消さずにそのまま使う。

### 3. 入口を置く

```bash
<スキルのパス>/scripts/write-supervisor-agents.sh "$SUPERVISOR_DIR"
```

`$SUPERVISOR_DIR/AGENTS.md`（supervisor が読むべき手順書と、全タスクディレクトリの親のパス）と、
それを `@` で読み込むだけの `CLAUDE.md` を生成する。タスクディレクトリの入口と同じく、
セッションをクリアされた supervisor が自分で手順書へ戻るためのものである（→ ADR 0005）。
タスクディレクトリの親が既定と違うなら、第 2 引数に絶対パスで渡す。
何度実行してもよい。手で書かれた同名ファイルは上書きしない。

### 4. workspace を作って起動する

```bash
herdr workspace create --cwd "$SUPERVISOR_DIR" --label herdr-supervisor --no-focus
herdr agent start supervisor --kind "$KIND" --pane "$ROOT_PANE"
```

`$ROOT_PANE` は `workspace create` の応答の `.result.root_pane.pane_id` から読む。推測しない。
`$KIND` の決め方は「呼び出し元の手順」5 と同じである。

### 5. 手順書を渡す

```bash
<スキルのパス>/scripts/prompt-agent.sh supervisor \
  "あなたは herdr-tasks の supervisor です。まず <スキルのパス>/supervisor.md を読み、手順 0 の前提確認を済ませてから、ユーザーの依頼を待ってください。"
```

exit 2 の場合は「プロンプトの着弾を確認する」の trust 確認手順に従う。cwd が今作った
`$SUPERVISOR_DIR` と一致する場合だけ承認する。

フォーカスは移さない。supervisor の agent 名（`herdr agent attach supervisor` で覗ける旨）と
ディレクトリのパスをユーザーに伝えて終わる。supervisor は起動しただけでは何もせず、
ユーザーに聞かれてから一覧を作る。

## プロンプトの着弾を確認する

**`herdr agent start` が `interactive_ready: true` を返しても、agent がプロンプトを受け付けられる
とは限らない。** 起動直後に `herdr agent prompt` を投げると、テキストがどこにも入らずに消えることが
ある。このとき `agent prompt` は `agent_prompted` を返して成功したように見えるため、投げっぱなしにすると
気づけない。coordinator を起動して沈黙する、worker が動き出さない、といった形で後から発覚する。

通常は `agent_session` の有無で見分ける。まだセッションが確定していない agent は応答に
`agent_session` を持たず、`revision` が `0` のままになる。

| | 受け付けられない状態 | 受け付けられる状態 |
|---|---|---|
| `agent_session` | 無し | `{"kind":"id","value":"..."}` |
| `revision` | `0` | `1` 以上 |

ただし Codex の一部バージョンは、最初のプロンプトを送るまで session ID を生成しない。
この場合に限り、`idle`、`interactive_ready: true`、`revision > 0` に加え、terminal に空の
`Ask Codex to do anything` 入力欄が見えていれば送信可能と判断する。送信後には必ず
`agent_session` が生成され、状態または revision が変化したことを確認する。

この判定を coordinator と worker の起動箇所で同じように行うため、
[`scripts/prompt-agent.sh`](scripts/prompt-agent.sh) を使う。スクリプトは次を行う。

- 送信前に session ID、または上記 Codex 入力欄のどちらかを待つ。
- プロンプトは1回だけ送る。
- 送信後に session ID と状態遷移を確認する。
- 確認できない場合は terminal 出力を表示して失敗する。重複送信は自動で行わない。

### ディレクトリの trust 確認で止まった場合

新しいタスクディレクトリや worktree で Codex を初めて起動すると、次の画面で止まることがある。

```text
Do you trust the contents of this directory?
```

`prompt-agent.sh` はこの状態を検出すると exit 2 で停止する。自動承認はしない。
`herdr agent get` の `cwd` が、このタスクのために自分が作成した `$TASK_DIR` または worker
worktree と完全一致することを確認する。一致した場合だけ、応答から得た `pane_id` に Enter を送り、
同じ `prompt-agent.sh` コマンドを再実行する。cwd が異なる、または内容を自分で用意していない場合は
承認せずユーザーへ確認する。

送信確認に失敗した場合も、スクリプトは同じプロンプトを自動再送しない。表示された terminal を読み、
入力欄に残っているだけなのか、agent がすでに処理したのかを確認してから再送可否を判断する。

## coordinator が停止した場合の再開

セッションのクリア、コンテキストの喪失、プロセスの停止で coordinator の会話文脈は失われる。
タスクディレクトリは固定パスに残るため、そこから読み直させれば再開できる。**呼び出し元の
会話文脈は必要ない。** 再開に必要な事実はすべてタスクディレクトリのファイルに書かれている
（→ ADR 0003）。

**セッションをクリアしただけなら、coordinator は自分で手順書へ戻る。** タスクディレクトリの
`AGENTS.md` / `CLAUDE.md` が新しいセッションの開始時に読み込まれ、役割と手順書のパスは
そこにある（→ ADR 0005）。以下は、agent プロセスそのものが失われた場合の手順である。

まず現状を確認する。workspace とタスクディレクトリのパスは TASK.md の「実行環境」にある。

```bash
herdr agent list
herdr workspace list
```

coordinator の agent がまだ生きているなら、プロンプトで `coordinator.md` と
`TASK.md` / `STATE.md` を読み直させるだけでよい。agent が失われている場合は、同じ workspace の
root pane に同じ名前で起動し直す。pane が残っていれば新しい tab は作らない。

```bash
herdr tab list --workspace "$WORKSPACE_ID"
```

応答から coordinator の tab の `root_pane.pane_id` を読む。`$COORD_NAME` と `$KIND` は
TASK.md の「実行環境」と命名規則から決まる。

```bash
herdr agent start "$COORD_NAME" --kind "$KIND" --pane "$ROOT_PANE"
<スキルのパス>/scripts/prompt-agent.sh "$COORD_NAME" \
  "あなたはこのタスクの coordinator です。これは中断からの再開です。まず <スキルのパス>/coordinator.md を読み、次に $TASK_DIR/TASK.md と $TASK_DIR/STATE.md を読んで、再開判定の手順から始めてください。"
```

worker は coordinator と別プロセスなので、coordinator が落ちても生き続けていることがある。
再開した coordinator が `herdr agent list` と STATE.md を突き合わせて判断するため、
呼び出し元やユーザーが worker を先に片付ける必要はない。

## ファイル

- `SKILL.md` — このファイル。呼び出し元の手順と全体像。
- `coordinator.md` — coordinator が読む手順書。
- `worker.md` — worker が読む手順書。
- `supervisor.md` — supervisor が読む手順書。
- `scripts/install-skill.sh` — `~/.agents/skills` と `~/.claude/skills` に symlink を張る。
- `scripts/prompt-agent.sh` — agent の入力待ち・trust 停止・プロンプト着弾を判定する。
- `scripts/write-task-agents.sh` — タスクディレクトリに `AGENTS.md` / `CLAUDE.md` を生成する。
- `scripts/write-supervisor-agents.sh` — supervisor ディレクトリに `AGENTS.md` / `CLAUDE.md` を生成する。
- `scripts/lib/agents-entry.sh` — 上の 2 つが共有する入口生成の処理（手書きファイルを上書きしない判定）。
- `templates/task-agents.md` — タスクディレクトリに生成される `AGENTS.md` の雛形。
- `templates/supervisor-agents.md` — supervisor ディレクトリに生成される `AGENTS.md` の雛形。
- `docs/adr/` — 設計判断の記録。
