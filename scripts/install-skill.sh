#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
skill_name="$(basename "${repo_root}")"

targets=(
  "${HOME}/.agents/skills"
  "${HOME}/.claude/skills"
)

if [[ ! -f "${repo_root}/SKILL.md" ]]; then
  echo "SKILL.md not found in: ${repo_root}" >&2
  exit 1
fi

has_conflict=0

for target_dir in "${targets[@]}"; do
  link_path="${target_dir}/${skill_name}"

  if [[ -L "${link_path}" ]]; then
    current_target="$(readlink "${link_path}")"
    if [[ "${current_target}" == "${repo_root}" ]]; then
      continue
    fi
    echo "conflict: ${link_path} is a symlink to ${current_target}" >&2
    has_conflict=1
    continue
  fi

  if [[ -e "${link_path}" ]]; then
    echo "conflict: ${link_path} already exists and is not a symlink" >&2
    has_conflict=1
  fi
done

if [[ ${has_conflict} -ne 0 ]]; then
  echo "aborting without changes because conflicts were found" >&2
  exit 1
fi

for target_dir in "${targets[@]}"; do
  mkdir -p "${target_dir}"
  link_path="${target_dir}/${skill_name}"

  if [[ -L "${link_path}" ]]; then
    echo "exists: ${link_path} -> ${repo_root}"
    continue
  fi

  ln -s "${repo_root}" "${link_path}"
  echo "linked: ${link_path} -> ${repo_root}"
done
