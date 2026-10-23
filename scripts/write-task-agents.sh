#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 <task-dir>" >&2
  exit 64
}

if [[ $# -ne 1 ]]; then
  usage
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
template="${skill_dir}/templates/task-agents.md"

# shellcheck source=lib/agents-entry.sh
source "${script_dir}/lib/agents-entry.sh"

if [[ ! -f "${template}" ]]; then
  echo "template not found: ${template}" >&2
  exit 1
fi

if [[ ! -d "$1" ]]; then
  echo "task directory not found: $1" >&2
  exit 1
fi

task_dir="$(cd "$1" && pwd)"

agents_md="$(cat "${template}")"
agents_md="${agents_md//@@SKILL_DIR@@/${skill_dir}}"
agents_md="${agents_md//@@TASK_DIR@@/${task_dir}}"

agents_entry_write "${task_dir}" "${agents_md}"
