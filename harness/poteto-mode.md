# poteto-mode を herdr で使う

`<poteto-mode>` は poteto-mode 本体の絶対パス（インストール後は `~/.agents/skills/poteto-mode`）。
本体の `SKILL.md` と選んだプレイブックを読み、この文書でサブエージェント操作を herdr に読み替える。
`<herdr-tasks>` はこの文書を同梱するスキルの絶対パス。

## herdr-tasks のタスクで有効にしたとき

`TASK.md` の「実行環境」に `- poteto-mode: 有効` があるタスクだけが対象。次を除き、
[coordinator.md](../coordinator.md) と [worker.md](../worker.md) の役割・運用は維持する。

- **進め方は poteto-mode。** Autonomy と選んだプレイブックが、herdr-tasks の要判断の条件、
  マージ前の承認、成果を伴う片付け前の確認に優先する。herdr-tasks 独自の承認を追加しない。
  人の判断を待つのは Autonomy の「元に戻せない書き込み」か、プレイブックが人に判断を渡す箇所
  （Babysit の「human's call」、Autopilot の operator gate など）だけ。明示的なユーザー指示、
  サンドボックス、権限、リポジトリや forge の保護はこの読み替えで解除しない。
- **要判断の記録は herdr-tasks。** 人の判断を待つときは coordinator が `coordinator.md` の
  「監視とエスカレーション」に従い、`STATE.md` の該当行、1 行目の状態行と「未解決の要判断」を
  更新し、通知と pane で伝える。worker は先に coordinator に届ける。手順書の「自力での解消を
  2 回」の規定を別の承認条件にしない。実行不能な手順を成功扱いせず、作業結果に理由を残す。
- **プレイブックを回すのは依頼を受け取ったセッション。** coordinator はプレイブックを選び、
  判断・分担・検証を行うが、対象リポジトリは編集しない。実装・テスト・PR 作成を要する手順は
  作業単位の worker に渡す。worker は渡された範囲のプレイブックを自分で回し、自分の PR を出す。
  マージを扱うプレイブックも担当単位と検証を保ち、実行可否は上記の承認ルールで決める。
- **1 PR = 1 worker は変えない。** パネル席や検証役は一時的な補助 agent で、PR の担当ではない。
  書き込む補助 agent が必要なら coordinator が管理する専用 worktree に隔離し、候補の差分・
  コミットを PR 担当 worker に渡す。補助 agent は PR を出さず、担当 worker が採否と検証を引き受ける。
- **タスクの記録は 3 ファイルのまま。** `TASK.md` に仕様、`STATE.md` に現在の作業単位と要判断、
  `PROGRESS.md` に日付つきの経緯を残す。プレイブックの中間成果や一時的な席の回収先は `notes/` に置く。
  再開時は記録と実体を突き合わせ、補助 agent を重複して立てない。

PR 担当 worker には `spawn` の kickoff 1 行目に続けて、`coordinator.md` の「プロンプトを送る」
にある herdr-tasks の `worker.md`、指示ファイル、`TASK.md` を読む順を伝える。poteto-mode の
`worker.md` は行動規則、herdr-tasks の `worker.md` は担当範囲・成果物・報告先の手順とし、
承認・エスカレーション・片付け前確認で食い違うときは上の規則に従う。立て直し時も同じ kickoff を使う。
補助 agent に herdr-tasks の PR 担当 worker の責務を課さない。

## 5 つの操作

| 操作 | herdr での扱い |
| --- | --- |
| **spawn** | [coordinator.md「worker を起動する」](../coordinator.md#6-worker-を起動する)の tab・pane・agent の起動手順に従う。タスクと同じ workspace に `herdr tab create` で開き、`herdr agent start` は `--kind pi` と以下のモデル引数を使う。kickoff 1 行目は `Read <poteto-mode>/worker.md before anything else.`（絶対パスに展開）とし、その後に役割、ゴール、指示・対象・結果ファイルへの絶対パスを渡す。kickoff の送信は `send` と同じ。 |
| **send** | [SKILL.md「プロンプトの着弾を確認する」](../SKILL.md#プロンプトの着弾を確認する)のとおり、`<herdr-tasks>/scripts/prompt-agent.sh` で着弾を確認する。指示を変える場合は先に指示ファイル（補助 agent は brief）に残す。応答が不明なときは同手順で確かめ、無条件に再送しない。 |
| **wait** | [coordinator.md「完了待ちはバックグラウンドに置く」](../coordinator.md#完了待ちはバックグラウンドに置く)を使う。全席に送ってから席ごとに `herdr agent wait` をバックグラウンドで張り、同節の 3 状態（`idle` / `done` / `blocked`）を対象にする。待ちが返ったら pane と成果物を確認する。停止だけでは成功ではない。 |
| **close** | 結果を回収してから、[coordinator.md「片付け」](../coordinator.md#11-片付け)の tab の閉じ方に従い、作成時に得た ID の tab だけを閉じる。隔離した worktree は本体の Worktree cleanup に沿って確認し、成果の退避後に `~/bin/herdr-task-worktree remove` で片付ける。未コミット・未追跡の変更を強制削除せず、無関係の tab や workspace を閉じない。有効タスクでは確認の要否は上記に従う。 |
| **isolate** | 書き込む席は `~/bin/herdr-task-worktree` で基点を指定して専用 worktree を作る。PR 担当 worker の配置と記録は [coordinator.md「worker を起動する」](../coordinator.md#6-worker-を起動する) に従う。補助 agent 用は `notes/poteto/<run-id>/worktrees/` に置き、PR 担当 worker の再開判定と混ぜない。プレイブックが未コミット差分も対象にするなら、起動前に専用 worktree へ持ち込む。 |

PR 担当 worker の名前・tab ラベルは [SKILL.md「命名規則」](../SKILL.md#命名規則) のとおり。
補助 agent は同じ slug・長さ・衝突回避の規則で、作業単位と席を識別できる名前にする
（例: tab `add-retry-interrogate-1`、agent `panel-add-retry-interrogate-1`）。`work-` は
PR 担当 worker に残す。タスクの中では起動元が、席の名前・brief・結果の回収先、隔離するなら
worktree のパスと基点を作成前に `notes/` に残す。作成後に tab・pane ID を記録し、回収と片付けも担当する。

### 結果と読み取り専用の席

読み取り専用の席には専用 worktree は不要。席の出力用ディレクトリを cwd にし、対象を絶対パスで渡す。
同じ対象を複数席に渡すなら、結果回収まで対象を変えない。リポジトリを編集したり、
生成物が対象に残るコマンドを実行したりしない。再現コマンドが対象を書き換えるなら読み取り専用ではなく
`isolate` を使う。読み取り専用は brief による制約で、herdr がファイル権限を変更するわけではない。

座席ごとの結果ファイルを先に指定する（例: `$TASK_DIR/notes/poteto/<run-id>/<seat>.md`）。
全席に同じ入力を渡す場合も、出力は共有しない。席は結果を指定ファイルに書き、最終応答で絶対パスを返す。
起動元がファイルの内容を読み、プレイブックが求める再検証と取りまとめを行う。pane だけに長い結果を残さない。

### モデルと effort

本体の `models.md` で役割ごとのモデルと effort を決める。pi へは `herdr agent start` の
`--` の後に `--model <provider>/<model>`、effort の指定があれば `--thinking <level>` を渡す。
指定のレベルを選んだモデルが受け付けない場合は、pi で使える範囲に読み替える。対応が無ければ
`--thinking` は省略し、その旨を報告する。モデルも代替した場合は明記し、指定席が動いたとは数えない。

## `/skill:poteto-mode` を単独で使うとき

herdr-tasks の管理外でも `HERDR_ENV=1` であれば、呼び出した pi が今の workspace 内で上の
5 操作を使える。タスクの枠や `TASK.md` は作らず、呼び出したセッションが席の起動・待機・回収・
片付けを持つ。結果や brief の置き場は書き込み可能な専用ディレクトリを選び、使うパスを kickoff で渡す。
書き込む席を隔離できない場合は、同じ checkout に書かせない。

`HERDR_ENV=1` でなければこの読み替えは使わない。使えるサブエージェント手段があれば本体の契約に
従って使い、無ければ単独でできる手順に限る。パネル等を実行できなかった箇所は結果に明記する。
