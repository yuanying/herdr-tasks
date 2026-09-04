#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

target="$script_dir/write-task-agents.sh"

exit_code_of() {
  set +e
  "$@" >/dev/null 2>&1
  local status=$?
  set -e
  printf '%s\n' "$status"
}

# 引数が無い場合は usage で止まる
test "$(exit_code_of "$target")" -eq 64

# 存在しないタスクディレクトリは拒否する
test "$(exit_code_of "$target" "$test_dir/missing")" -ne 0

# 正常系: 2 つのファイルを生成する
task_dir="$test_dir/#42-add-retry"
mkdir -p "$task_dir"
"$target" "$task_dir" >/dev/null

test -f "$task_dir/AGENTS.md"
test -f "$task_dir/CLAUDE.md"

# CLAUDE.md は AGENTS.md を @ でインポートするだけ
grep -qx '@AGENTS.md' "$task_dir/CLAUDE.md"

# 生成物にはスキルとタスクディレクトリの絶対パスが入り、プレースホルダは残らない
grep -qF "$repo_root" "$task_dir/AGENTS.md"
grep -qF "$task_dir" "$task_dir/AGENTS.md"
grep -qF 'coordinator.md' "$task_dir/AGENTS.md"
grep -qF 'worker.md' "$task_dir/AGENTS.md"
! grep -q '@@' "$task_dir/AGENTS.md"

# 冪等: 再実行しても内容が変わらない
cp "$task_dir/AGENTS.md" "$test_dir/agents-first-run.md"
cp "$task_dir/CLAUDE.md" "$test_dir/claude-first-run.md"
"$target" "$task_dir" >/dev/null
cmp -s "$test_dir/agents-first-run.md" "$task_dir/AGENTS.md"
cmp -s "$test_dir/claude-first-run.md" "$task_dir/CLAUDE.md"

# 手で書かれたファイルは上書きせず、何も変更せずに中止する
handwritten_dir="$test_dir/handwritten"
mkdir -p "$handwritten_dir"
printf '%s\n' 'ユーザーが書いた規約' >"$handwritten_dir/AGENTS.md"
test "$(exit_code_of "$target" "$handwritten_dir")" -ne 0
grep -qx 'ユーザーが書いた規約' "$handwritten_dir/AGENTS.md"
test ! -f "$handwritten_dir/CLAUDE.md"

# CLAUDE.md だけが手書きの場合も同じく中止する
claude_only_dir="$test_dir/claude-only"
mkdir -p "$claude_only_dir"
printf '%s\n' '@SOMETHING_ELSE.md' >"$claude_only_dir/CLAUDE.md"
test "$(exit_code_of "$target" "$claude_only_dir")" -ne 0
test ! -f "$claude_only_dir/AGENTS.md"

echo "write-task-agents tests passed"
