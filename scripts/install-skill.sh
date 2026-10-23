#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

targets=(
  "${HOME}/.agents/skills"
  "${HOME}/.claude/skills"
)

# リンク名とリンク先の組。herdr-tasks 本体と、同じリポジトリに同梱した skills/* を張る。
skill_names=("$(basename "${repo_root}")")
skill_sources=("${repo_root}")

for skill_dir in "${repo_root}"/skills/*/; do
  [[ -d "${skill_dir}" ]] || continue
  skill_dir="${skill_dir%/}"
  skill_names+=("$(basename "${skill_dir}")")
  skill_sources+=("${skill_dir}")
done

for source in "${skill_sources[@]}"; do
  if [[ ! -f "${source}/SKILL.md" ]]; then
    echo "SKILL.md not found in: ${source}" >&2
    exit 1
  fi
done

has_conflict=0

for target_dir in "${targets[@]}"; do
  for i in "${!skill_names[@]}"; do
    link_path="${target_dir}/${skill_names[$i]}"
    source="${skill_sources[$i]}"

    if [[ -L "${link_path}" ]]; then
      current_target="$(readlink "${link_path}")"
      if [[ "${current_target}" == "${source}" ]]; then
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
done

if [[ ${has_conflict} -ne 0 ]]; then
  echo "aborting without changes because conflicts were found" >&2
  exit 1
fi

for target_dir in "${targets[@]}"; do
  mkdir -p "${target_dir}"

  for i in "${!skill_names[@]}"; do
    link_path="${target_dir}/${skill_names[$i]}"
    source="${skill_sources[$i]}"

    if [[ -L "${link_path}" ]]; then
      echo "exists: ${link_path} -> ${source}"
      continue
    fi

    ln -s "${source}" "${link_path}"
    echo "linked: ${link_path} -> ${source}"
  done
done
