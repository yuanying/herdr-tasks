# 0003. coordinator の会話文脈が失われても再開できる状態をタスクディレクトリに残す

- Date: 2026-08-21
- Status: Accepted

## Context

coordinator は agent プロセスであり、セッションのクリア・コンテキスト溢れ・プロセス停止で
会話文脈を失う。ADR 0001 の時点から「coordinator と worker の間で渡せるのはファイルのパスだけ」
という制約は認識していたが、同じ制約が **停止前の coordinator と再開後の coordinator の間** にも
成り立つことを扱っていなかった。

TASK_DIR は固定パスに残るため、TASK.md・PROGRESS.md・notes/・worktree・branch は生き残る。
しかし再開に必要な次の事実は、これまで coordinator の会話文脈にしか存在しなかった。

- 各 worker に渡した指示の本文（担当範囲・依存・前提）。PROGRESS.md には worker 名しかないため、
  再開後は差し戻しも再送もできない。
- 検証時の比較起点となる base コミット。「デフォルトブランチの最新」は時間で動くため、
  再開後に同じ差分を再現できない。
- スキルのパス、agent kind、workspace ID。worker を立て直すときに必要になる。
- エスカレーションの有無。ユーザーへ何を問い合わせて待っているのかが失われる。

さらに PROGRESS.md を副作用の後に更新する規律では、tab 作成から記録までの間に停止すると、
記録に無い worktree や tab が残り、再開した coordinator がそれを認識できない。

## Decision

- 再開に必要な事実は、すべて TASK_DIR 配下のファイルに置く。coordinator の記憶を前提にしない。
- 保存先は既存の TASK.md と PROGRESS.md を拡張して賄い、機械可読な状態ファイルは別に持たない。
  人間が読む記録と再開に使う記録を二重管理しないことを優先する。
- PROGRESS.md の状態表に、base コミット・agent kind・差し戻し回数を項目として加える。
- TASK.md に「実行環境」の節を設け、スキルのパス・agent kind・workspace ID を記録する。
- worker への指示は `notes/workers/<worker 名>.md` に書いてから渡し、プロンプトではそのパスを参照する。
  差し戻し・再送・再開はすべて同じファイルを起点にする。
- PROGRESS.md は write-ahead で更新する。worktree・tab・agent を作る前に意図を書き、
  作成後に応答から得た ID を埋める。これにより「記録はあるが実体がない」「実体はあるが記録がない」の
  両方を再開時に検出できる。
- coordinator は起動時にまず再開かどうかを判定する。PROGRESS.md の記録と、worktree・tab・agent の
  実在を突き合わせ、生存している worker には再接続し、失われた worker だけを立て直す。

## Consequences

- coordinator は停止しても、同じ workspace で agent を起動し直して手順書とタスクディレクトリを
  読ませれば作業を継続できる。呼び出し元の会話文脈も不要になる。
- 状態表の項目が増え、coordinator が書く量と更新の手間が増える。write-ahead により、
  実体を作らずに終わった行が一時的に残ることも許容する。
- 記録は自然言語のままなので、再開時の突き合わせは coordinator の読み取りに依存する。
  厳密な機械処理が必要になった場合は、この判断を見直して状態ファイルの導入を再検討する。
- worker への指示がファイルとして残るため、タスク完了後もどの範囲を誰に任せたのかを追跡できる。
