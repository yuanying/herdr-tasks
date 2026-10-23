---
name: herdr-supervisor
description: >-
  herdr-tasks の全タスクを束ねる supervisor を起動する。すでに起動していれば、その
  workspace を教える。トリガー: "herdr-supervisor", "/herdr-supervisor",
  "supervisor を起動して", "supervisor を立てて", "supervisor はどこ"。使用場面:
  (1) herdr-tasks のタスクが増えて全体を一望したい、(2) タスク同士の依存や衝突を
  管理させたい、(3) 起動済みの supervisor の居場所を知りたい
---

# herdr-supervisor

herdr-tasks のタスクが増えると、どれが走っていて、どれが判断待ちで、どれが止まっているかを
一望できなくなる。タスク同士の関係（あるタスクが別タスクの PR を待つ、複数のタスクが同じ
リポジトリを触る）を置く場所も無い。各 coordinator は自分のタスクしか見ていないからである。
これを受け持つのが **supervisor** である。

このスキルが行うのは **起動と、起動済みの supervisor の案内だけ** である。supervisor が
何をし、何をしないかは herdr-tasks の `supervisor.md` にあり、設計の理由は
`docs/adr/0006-supervisor-across-tasks.md` にある。

## 前提条件

```bash
test "${HERDR_ENV:-}" = 1
```

これが失敗する場合は herdr の中にいない。その旨を伝えて中止する。

## herdr-tasks のパスを解決する

このスキルは herdr-tasks リポジトリの `skills/herdr-supervisor/` に同梱されている。
スクリプトと `supervisor.md` は herdr-tasks 側のものを使う。

スキルの置き場（`~/.agents/skills/herdr-supervisor` など）は、そのディレクトリへの symlink
であることが多い。**symlink を実体へ解決してから親へ上がる。** 論理パスのまま `../..` を
辿ると、symlink の置き場の親（`~/.agents`）に出てしまう。

```bash
HERDR_TASKS_DIR="$(cd -P "<このスキルのパス>" && cd ../.. && pwd)"
test -f "$HERDR_TASKS_DIR/supervisor.md"
```

`<このスキルのパス>` はこの SKILL.md が置かれているディレクトリの絶対パスに置き換える。
`cd -P` が symlink を解決し、その後の `cd ../..` は実体の側で親へ上がる。
`supervisor.md` が見つからなければ、置き場が想定と違う。推測で進めずユーザーに伝える。

## 名前

| 用途 | 値 |
|---|---|
| workspace ラベル | `herdr-supervisor` |
| agent 名 | `supervisor` |
| 専用ディレクトリ | `~/.local/state/herdr-supervisor/`（推奨） |

**supervisor は全体で 1 つだけ立てる。** 名前を固定しているのは、既に居るかどうかを
この名前で引くためである。

## 1. 既に居ないか確かめる

```bash
herdr workspace list
herdr agent list
```

ラベル `herdr-supervisor` の workspace と、名前 `supervisor` の agent を探す。

- **agent が生きている** — 新しく立てない。workspace ID とラベル、
  `herdr agent attach supervisor` で覗ける旨をユーザーに伝えて終わる。
- **workspace だけが残り、agent が無い** — `herdr tab list --workspace <その workspace ID>` で
  root pane を読み、手順 4 の `herdr agent start` から起動し直す。専用ディレクトリと入口は
  残っているはずだが、手順 3 は何度実行してもよいので通しておく。
- **どちらも無い** — 手順 2 から進める。

## 2. 専用ディレクトリを作る

```bash
SUPERVISOR_DIR="$HOME/.local/state/herdr-supervisor"
mkdir -p "$SUPERVISOR_DIR"
```

**タスクディレクトリの親（`~/.local/state/herdr-tasks/`）の中には作らない。** supervisor は
そこを走査して一覧を作るため、中に置くと自分自身がタスクとして混ざる。
既にディレクトリがあれば、前の supervisor の記録が残っている。消さずにそのまま使う。

## 3. 入口を置く

```bash
"$HERDR_TASKS_DIR/scripts/write-supervisor-agents.sh" "$SUPERVISOR_DIR"
```

`$SUPERVISOR_DIR/AGENTS.md`（supervisor が読むべき手順書と、全タスクディレクトリの親のパス）と、
それを `@` で読み込むだけの `CLAUDE.md` を生成する。セッションをクリアされた supervisor が、
次のセッションの開始時にこれを読んで自分で手順書へ戻る（→ herdr-tasks の ADR 0005）。
タスクディレクトリの親が既定と違うなら、第 2 引数に絶対パスで渡す。
何度実行してもよい。手で書かれた同名ファイルは上書きしない。

## 4. workspace を作って起動する

```bash
herdr workspace create --cwd "$SUPERVISOR_DIR" --label herdr-supervisor --no-focus
herdr agent start supervisor --kind "$KIND" --pane "$ROOT_PANE"
```

`$ROOT_PANE` は `workspace create` の応答の `.result.root_pane.pane_id` から読む。推測しない。
`$KIND` は呼び出し元と同じ kind を既定とする。`herdr agent list` の中から `pane_id` が
`$HERDR_PANE_ID` のエントリを探し、その `agent` を使う。ユーザーから指定があればそれを優先する。

## 5. 手順書を渡す

```bash
"$HERDR_TASKS_DIR/scripts/prompt-agent.sh" supervisor \
  "あなたは herdr-tasks の supervisor です。まず $HERDR_TASKS_DIR/supervisor.md を読み、手順 0 の前提確認を済ませてから、ユーザーの依頼を待ってください。"
```

`prompt-agent.sh` は agent がプロンプトを受け付けられるまで待ち、送信後に着弾を確認する
（→ herdr-tasks の `SKILL.md`「プロンプトの着弾を確認する」）。exit 2 は directory trust の
確認で止まっている。agent の `cwd` が今作った `$SUPERVISOR_DIR` と一致する場合だけ承認し、
同じコマンドを再実行する。

## 6. 伝えて終わる

フォーカスは移さない。ユーザーに次を伝える。

- workspace ID とラベル `herdr-supervisor`
- agent 名 `supervisor`（`herdr agent attach supervisor` で覗ける旨）
- 専用ディレクトリのパス

supervisor は起動しただけでは何もしない。ユーザーに聞かれてから一覧を作る。
