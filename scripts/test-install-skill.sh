#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
skill_name="$(basename "${repo_root}")"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

target="$script_dir/install-skill.sh"

exit_code_of() {
  set +e
  "$@" >/dev/null 2>&1
  local status=$?
  set -e
  printf '%s\n' "$status"
}

skill_dirs=(".agents/skills" ".claude/skills")

# 正常系: 両方のスキルを両方の置き場に symlink する
fresh_home="$test_dir/fresh"
mkdir -p "$fresh_home"
HOME="$fresh_home" "$target" >/dev/null

for dir in "${skill_dirs[@]}"; do
  test "$(readlink "$fresh_home/$dir/$skill_name")" = "$repo_root"
  test "$(readlink "$fresh_home/$dir/herdr-supervisor")" = "$repo_root/skills/herdr-supervisor"
  test -f "$fresh_home/$dir/herdr-supervisor/SKILL.md"
done

# 冪等: 再実行しても成功し、リンク先は変わらない
HOME="$fresh_home" "$target" >/dev/null
for dir in "${skill_dirs[@]}"; do
  test "$(readlink "$fresh_home/$dir/herdr-supervisor")" = "$repo_root/skills/herdr-supervisor"
done

# herdr-tasks だけが入っている既存環境には herdr-supervisor を足す
partial_home="$test_dir/partial"
for dir in "${skill_dirs[@]}"; do
  mkdir -p "$partial_home/$dir"
  ln -s "$repo_root" "$partial_home/$dir/$skill_name"
done
HOME="$partial_home" "$target" >/dev/null
for dir in "${skill_dirs[@]}"; do
  test "$(readlink "$partial_home/$dir/herdr-supervisor")" = "$repo_root/skills/herdr-supervisor"
done

# 別の実体があれば、何も変更せずに中止する
conflict_home="$test_dir/conflict"
mkdir -p "$conflict_home/.claude/skills/herdr-supervisor"
test "$(exit_code_of env HOME="$conflict_home" "$target")" -ne 0
test ! -e "$conflict_home/.agents/skills/$skill_name"
test ! -e "$conflict_home/.agents/skills/herdr-supervisor"
test ! -e "$conflict_home/.claude/skills/$skill_name"
test ! -L "$conflict_home/.claude/skills/herdr-supervisor"

# 別の場所を指す symlink も衝突として扱う
other_link_home="$test_dir/other-link"
mkdir -p "$other_link_home/.agents/skills"
ln -s "$test_dir" "$other_link_home/.agents/skills/herdr-supervisor"
test "$(exit_code_of env HOME="$other_link_home" "$target")" -ne 0
test "$(readlink "$other_link_home/.agents/skills/herdr-supervisor")" = "$test_dir"
test ! -e "$other_link_home/.agents/skills/$skill_name"

echo "install-skill tests passed"
