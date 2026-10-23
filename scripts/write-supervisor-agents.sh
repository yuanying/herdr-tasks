#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 <supervisor-dir> [<tasks-root>]" >&2
  echo "  <tasks-root> defaults to \$HOME/.local/state/herdr-tasks and must be absolute" >&2
  exit 64
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
template="${skill_dir}/templates/supervisor-agents.md"

# shellcheck source=lib/agents-entry.sh
source "${script_dir}/lib/agents-entry.sh"

tasks_root="${2:-${HOME}/.local/state/herdr-tasks}"

if [[ "${tasks_root}" != /* ]]; then
  usage
fi

if [[ ! -f "${template}" ]]; then
  echo "template not found: ${template}" >&2
  exit 1
fi

if [[ ! -d "$1" ]]; then
  echo "supervisor directory not found: $1" >&2
  exit 1
fi

supervisor_dir="$(cd "$1" && pwd)"

# タスクの親ディレクトリはまだ無くてもよい。あれば実パスに揃えて比較する。
if [[ -d "${tasks_root}" ]]; then
  tasks_root="$(cd "${tasks_root}" && pwd)"
fi
tasks_root="${tasks_root%/}"

if [[ "${supervisor_dir}" == "${tasks_root}" || "${supervisor_dir}" == "${tasks_root}/"* ]]; then
  echo "supervisor directory must be outside the tasks root: ${tasks_root}" >&2
  exit 1
fi

agents_md="$(cat "${template}")"
agents_md="${agents_md//@@SKILL_DIR@@/${skill_dir}}"
agents_md="${agents_md//@@SUPERVISOR_DIR@@/${supervisor_dir}}"
agents_md="${agents_md//@@TASKS_ROOT@@/${tasks_root}}"

agents_entry_write "${supervisor_dir}" "${agents_md}"
