#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 <agent-name> <prompt>" >&2
  exit 64
}

if [[ $# -ne 2 ]]; then
  usage
fi

agent_name="$1"
prompt="$2"
ready_without_session=false
before_revision=0

for _ in $(seq 1 60); do
  if ! agent_json="$(herdr agent get "$agent_name" 2>/dev/null)"; then
    sleep 1
    continue
  fi

  agent_session="$(jq -r '.result.agent.agent_session.value // empty' <<<"$agent_json")"
  agent_state="$(jq -r '.result.agent.agent_status // "unknown"' <<<"$agent_json")"
  agent_revision="$(jq -r '.result.agent.revision // 0' <<<"$agent_json")"
  interactive_ready="$(jq -r '.result.agent.interactive_ready // false' <<<"$agent_json")"

  if [[ -n "$agent_session" ]]; then
    before_revision="$agent_revision"
    break
  fi

  recent_output="$(herdr agent read "$agent_name" --source recent --lines 80 2>/dev/null || true)"
  if grep -Fq 'Do you trust the contents of this directory?' <<<"$recent_output"; then
    cat >&2 <<EOF
agent $agent_name is waiting for a directory trust decision.
Verify the agent cwd, accept the prompt only when it is the task directory or
worktree you just created, and then run this command again.
EOF
    exit 2
  fi

  # Some Codex versions create their session on the first submitted prompt.
  # In that state, the visible empty input is the readiness signal.
  if [[ "$agent_state" == "idle" && "$interactive_ready" == "true" \
        && "$agent_revision" -gt 0 ]] \
     && grep -Fq 'Ask Codex to do anything' <<<"$recent_output"; then
    ready_without_session=true
    before_revision="$agent_revision"
    break
  fi

  sleep 1
done

if [[ -z "${agent_json:-}" ]]; then
  echo "agent $agent_name was not found" >&2
  exit 1
fi

if [[ -z "${agent_session:-}" && "$ready_without_session" != "true" ]]; then
  herdr agent read "$agent_name" --source recent --lines 80 >&2 || true
  echo "agent $agent_name did not become ready for a prompt" >&2
  exit 1
fi

herdr agent prompt "$agent_name" "$prompt" >/dev/null

for _ in $(seq 1 30); do
  agent_json="$(herdr agent get "$agent_name")"
  agent_session="$(jq -r '.result.agent.agent_session.value // empty' <<<"$agent_json")"
  agent_state="$(jq -r '.result.agent.agent_status // "unknown"' <<<"$agent_json")"
  agent_revision="$(jq -r '.result.agent.revision // 0' <<<"$agent_json")"

  case "$agent_state" in
    working|blocked|done)
      if [[ -n "$agent_session" ]]; then
        printf '%s\n' "$agent_json"
        exit 0
      fi
      ;;
    idle)
      # A very short task can finish before the first poll observes `working`.
      if [[ -n "$agent_session" && "$agent_revision" -gt "$before_revision" ]]; then
        printf '%s\n' "$agent_json"
        exit 0
      fi
      ;;
  esac

  sleep 1
done


herdr agent read "$agent_name" --source recent --lines 80 >&2 || true
cat >&2 <<EOF
prompt delivery to agent $agent_name could not be confirmed.
Inspect the output above before deciding whether it is safe to resend.
EOF
exit 1
