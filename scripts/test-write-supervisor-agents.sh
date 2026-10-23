#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

target="$script_dir/write-supervisor-agents.sh"

exit_code_of() {
  set +e
  "$@" >/dev/null 2>&1
  local status=$?
  set -e
  printf '%s\n' "$status"
}

# 引数が無い・多すぎる場合は usage で止まる
test "$(exit_code_of "$target")" -eq 64
test "$(exit_code_of "$target" a b c)" -eq 64

# 存在しない supervisor ディレクトリは拒否する
test "$(exit_code_of "$target" "$test_dir/missing")" -ne 0

# 正常系: タスクの親ディレクトリを省略すると ~/.local/state/herdr-tasks を使う
fake_home="$test_dir/home"
supervisor_dir="$fake_home/.local/state/herdr-supervisor"
mkdir -p "$supervisor_dir"
HOME="$fake_home" "$target" "$supervisor_dir" >/dev/null

test -f "$supervisor_dir/AGENTS.md"
test -f "$supervisor_dir/CLAUDE.md"

# CLAUDE.md は AGENTS.md を @ でインポートするだけ
grep -qx '@AGENTS.md' "$supervisor_dir/CLAUDE.md"

# 生成物にはスキル・supervisor ディレクトリ・タスクの親ディレクトリの絶対パスが入る
grep -qF "$repo_root" "$supervisor_dir/AGENTS.md"
grep -qF "$supervisor_dir" "$supervisor_dir/AGENTS.md"
grep -qF "$fake_home/.local/state/herdr-tasks" "$supervisor_dir/AGENTS.md"
grep -qF 'supervisor.md' "$supervisor_dir/AGENTS.md"
grep -qF 'RELATIONS.md' "$supervisor_dir/AGENTS.md"
! grep -q '@@' "$supervisor_dir/AGENTS.md"

# タスクディレクトリ用の入口とは別物である（coordinator / worker の手順書へ誘導しない）
! grep -qF 'worker.md' "$supervisor_dir/AGENTS.md"

# 冪等: 再実行しても内容が変わらない
cp "$supervisor_dir/AGENTS.md" "$test_dir/agents-first-run.md"
cp "$supervisor_dir/CLAUDE.md" "$test_dir/claude-first-run.md"
HOME="$fake_home" "$target" "$supervisor_dir" >/dev/null
cmp -s "$test_dir/agents-first-run.md" "$supervisor_dir/AGENTS.md"
cmp -s "$test_dir/claude-first-run.md" "$supervisor_dir/CLAUDE.md"

# タスクの親ディレクトリを明示できる。まだ存在しなくてもよい
explicit_dir="$test_dir/explicit"
mkdir -p "$explicit_dir"
"$target" "$explicit_dir" "$test_dir/tasks-not-yet-created" >/dev/null
grep -qF "$test_dir/tasks-not-yet-created" "$explicit_dir/AGENTS.md"

# タスクの親ディレクトリは絶対パスでなければ拒否する
relative_dir="$test_dir/relative"
mkdir -p "$relative_dir"
test "$(exit_code_of "$target" "$relative_dir" relative/tasks)" -eq 64
test ! -f "$relative_dir/AGENTS.md"

# supervisor ディレクトリをタスクの親ディレクトリの中に置くと拒否する
# （タスク一覧に supervisor 自身が混ざる）
tasks_root="$test_dir/tasks"
inside_dir="$tasks_root/herdr-supervisor"
mkdir -p "$inside_dir"
test "$(exit_code_of "$target" "$inside_dir" "$tasks_root")" -ne 0
test ! -f "$inside_dir/AGENTS.md"

# 手で書かれたファイルは上書きせず、何も変更せずに中止する
handwritten_dir="$test_dir/handwritten"
mkdir -p "$handwritten_dir"
printf '%s\n' 'ユーザーが書いた規約' >"$handwritten_dir/AGENTS.md"
test "$(exit_code_of "$target" "$handwritten_dir" "$tasks_root")" -ne 0
grep -qx 'ユーザーが書いた規約' "$handwritten_dir/AGENTS.md"
test ! -f "$handwritten_dir/CLAUDE.md"

# CLAUDE.md だけが手書きの場合も同じく中止する
claude_only_dir="$test_dir/claude-only"
mkdir -p "$claude_only_dir"
printf '%s\n' '@SOMETHING_ELSE.md' >"$claude_only_dir/CLAUDE.md"
test "$(exit_code_of "$target" "$claude_only_dir" "$tasks_root")" -ne 0
test ! -f "$claude_only_dir/AGENTS.md"

echo "write-supervisor-agents tests passed"
