# 0007. poteto-mode の実行方針をタスク単位で選ぶ

- Date: 2026-11-27
- Status: Accepted

## Context

poteto-mode は、依頼に応じてプレイブックを選ぶスキルで、並行レビューや設計比較で
サブエージェントを使う。取り込み元は Cursor のサブエージェント起動機能を使うため、
herdr の独立した pane で pi を起動する運用にはそのまま使えない。
また、poteto-mode は原則として可逆な作業を自律的に進めるが、herdr-tasks の標準運用は
マージや成果を伴う片付けの前にユーザー承認を求める。両方の規則を同時に適用すると、
同じプレイブックでも止まる場所が変わる。

## Decision

- 本体はプレイブックとサブエージェントの操作契約を持ち、herdr-tasks はその操作を
  自分の起動・監視手順に対応づける。具体的な手順の正は herdr-tasks に置く。
- ユーザーが選んだタスクだけ、タスク仕様書で poteto-mode を有効にする。有効な場合は
  要判断・マージ前の承認・片付け前の確認を poteto-mode の Autonomy とプレイブックに委ねる。
  元に戻せない書き込みとプレイブックが人に返す箇所で停止する。権限や保護設定は変更しない。
  有効化されていないタスクでは、片付け前の確認を含めて herdr-tasks の標準運用を変えない。
- 有効なタスクでも、coordinator は実装せず、PR は担当 worker が出す。パネルなどの補助 agent は
  PR の責任を持たない。要判断を含むタスクの状態は従来の記録を使い、別の進捗管理を作らない。

### 本 ADR で決定しないこと

- サブエージェントの起動方法、設定の書式、結果の受け渡し（委譲先は「poteto-mode を herdr で使う」）。
- モデル選択とプレイブックの詳細（委譲先は poteto-mode 本体）。

## Consequences

poteto-mode の進め方を選んでも、標準タスクの承認や既存の再開手順を全体で変更せずに済む。
一方、有効なタスクには本体と読み替えの両方が必要になり、操作契約を変えるときは両方の整合を確認する。
有効化を明記したタスクで必要な文書が見つからない場合は、標準運用に黙って戻さず、欠落を報告して止まる。

## Related ADRs

- Related: [ADR 0002「1 タスクを 1 workspace とし、作業リポジトリを tab にまとめる」](0002-task-workspace-with-repository-tabs.md)。workspace の構成は維持し、片付け前の承認だけ有効タスクを標準運用の適用外とする。
- Related: [ADR 0004「worker のライフサイクルは 1 PR で閉じる」](0004-worker-lifecycle.md)。PR 担当 worker の責務は維持する。

## References

- [取り込み元 Poteto mode「Autonomy」「Subagents」](https://github.com/cursor/plugins/blob/b7b93c3/pstack/skills/poteto-mode/SKILL.md)（2026-11-27 確認）
- [取り込み元 pstack in Claude Code](https://github.com/cursor/plugins/blob/b7b93c3/pstack/docs/harness/claude-code.md)（2026-11-27 確認）
- [coordinator 手順書「監視とエスカレーション」「片付け」](../../coordinator.md)（2026-11-27 確認）
- [poteto-mode を herdr で使う](../../harness/poteto-mode.md)（2026-11-27 確認）
