---
name: herdr-tasks
description: herdr の workspace / worktree を使って、与えられたタスクを完遂まで面倒を見る。トリガー: "herdr-tasks", "/herdr-tasks", "herdr でタスクを進めて", "このタスクを別 workspace でやって"。使用場面: (1) 独立したタスクを専用 workspace に切り出したい、(2) 複数リポジトリにまたがる修正、(3) 時間のかかる実装を別セッションに任せて手元を空けたい
---

# herdr-tasks

タスクを受け取ったら、herdr 上に専用の workspace を作り、そこに常駐する **coordinator** に
タスク完遂までの責任を持たせる。対象が複数リポジトリにまたがる場合は、リポジトリごとに
worktree を切って **worker** を立て、coordinator がそれらを取りまとめる。

このスキルは特定の Coding Agent に依存しない。`herdr` CLI と `git`、`ghq` があれば動く。

## 役割

| 役割 | 居場所 | 責任 |
|---|---|---|
| 呼び出し元 | 現在の pane | タスク仕様書を書き、coordinator を起動し、起動報告をして手を引く |
| coordinator | タスク専用 workspace | タスク完遂までの責任。worker の起動・監視・検証・取りまとめ |
| worker | リポジトリごとの worktree workspace | 担当リポジトリの実装・テスト・コミット |

- 対象リポジトリが coordinator のいるリポジトリ 1 つだけなら、worker は立てず coordinator が自分で実装する。
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
| worker workspace ラベル | `<タスク名>/<リポジトリ名>` | `#42-add-retry-to-uploader/herdr` |
| ブランチ名 | `issue-<issue番号>-<slug>` / `<slug>` | `issue-42-add-retry-to-uploader` |
| タスクディレクトリ | `~/.local/state/herdr-tasks/<タスク名>/` | |
| coordinator agent 名 | `coord-` + 短縮 | `coord-42-add-retry` |
| worker agent 名 | `work-` + 短縮 + `-` + リポジトリ名 | `work-42-herdr` |

- slug は英小文字・数字・ハイフンで、タスク内容が読み取れる 3〜5 語程度にする。
- ブランチ名に `#` は使わない。ディレクトリ名と workspace ラベルには使う（シェルでは必ずクォートする）。
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

呼び出し元が git 作業ツリーの中にいるかで分岐する。

**リポジトリ内の場合** — そのリポジトリの worktree を coordinator の居場所にする。

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
git -C "$REPO_ROOT" fetch origin        # remote がある場合
herdr worktree create --cwd "$REPO_ROOT" --branch "$BRANCH" --base <デフォルトブランチの最新> \
  --label "$TASK_NAME" --no-focus
```

**リポジトリ外の場合** — 現在のディレクトリで workspace だけ作る。

```bash
herdr workspace create --cwd "$PWD" --label "$TASK_NAME" --no-focus
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

```bash
herdr agent prompt "$COORD_NAME" "あなたはこのタスクの coordinator です。まず <スキルのパス>/coordinator.md を読み、次に $TASK_DIR/TASK.md を読み、その手順に従ってタスクを完遂してください。"
```

`<スキルのパス>` はこの SKILL.md が置かれているディレクトリの絶対パスに置き換える。

### 8. 報告して終わる

フォーカスは移さない。ユーザーに以下を伝えて終了する。

- タスク名と workspace ラベル
- coordinator の agent 名（`herdr agent attach <名前>` で覗ける旨）
- タスクディレクトリのパス
- 対象リポジトリ（判明している分）

以降の進捗は coordinator が持つ。呼び出し元はこのタスクを監視しない。

## coordinator が停止した場合の再開

タスクディレクトリは固定パスに残るため、同じ workspace の pane で agent を起動し直し、
`coordinator.md` と `TASK.md`、`PROGRESS.md` を読ませれば再開できる。

## ファイル

- `SKILL.md` — このファイル。呼び出し元の手順と全体像。
- `coordinator.md` — coordinator が読む手順書。
- `worker.md` — worker が読む手順書。
- `scripts/install-skill.sh` — `~/.agents/skills` と `~/.claude/skills` に symlink を張る。
- `docs/adr/` — 設計判断の記録。
