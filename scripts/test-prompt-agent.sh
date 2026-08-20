#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

command_group="$1"
command_name="$2"
shift 2

if [[ "$command_group $command_name" == "agent get" ]]; then
  if [[ -f "$FAKE_STATE_DIR/prompted" ]]; then
    printf '%s\n' '{"result":{"agent":{"agent_session":{"value":"session-1"},"agent_status":"working","interactive_ready":true,"revision":2}}}'
  elif [[ "$SCENARIO" == "session" ]]; then
    printf '%s\n' '{"result":{"agent":{"agent_session":{"value":"session-1"},"agent_status":"idle","interactive_ready":true,"revision":1}}}'
  elif [[ "$SCENARIO" == "codex" ]]; then
    printf '%s\n' '{"result":{"agent":{"agent_status":"idle","interactive_ready":true,"revision":1}}}'
  else
    printf '%s\n' '{"result":{"agent":{"agent_status":"idle","interactive_ready":true,"revision":0}}}'
  fi
elif [[ "$command_group $command_name" == "agent read" ]]; then
  if [[ "$SCENARIO" == "trust" ]]; then
    printf '%s\n' 'Do you trust the contents of this directory?'
  else
    printf '%s\n' 'Ask Codex to do anything'
  fi
elif [[ "$command_group $command_name" == "agent prompt" ]]; then
  touch "$FAKE_STATE_DIR/prompted"
else
  echo "unexpected fake herdr command: $command_group $command_name" >&2
  exit 1
fi
EOF
chmod +x "$test_dir/bin/herdr"

run_success_case() {
  local scenario_name="$1" case_dir="$test_dir/$1"
  mkdir -p "$case_dir"
  PATH="$test_dir/bin:$PATH" FAKE_STATE_DIR="$case_dir" SCENARIO="$scenario_name" \
    "$script_dir/prompt-agent.sh" test-agent 'test prompt' >/dev/null
  test -f "$case_dir/prompted"
}

run_success_case session
run_success_case codex

trust_dir="$test_dir/trust"
mkdir -p "$trust_dir"
set +e
PATH="$test_dir/bin:$PATH" FAKE_STATE_DIR="$trust_dir" SCENARIO=trust \
  "$script_dir/prompt-agent.sh" test-agent 'test prompt' >/dev/null 2>&1
trust_exit=$?
set -e

test "$trust_exit" -eq 2
test ! -f "$trust_dir/prompted"

echo "prompt-agent tests passed"
