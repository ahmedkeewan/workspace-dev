#!/usr/bin/env bash
# Dependency-free checks of bin/dev's slot, port and secrets logic (no docker needed).
#   tests/test.sh
set -uo pipefail

SRC=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
fails=0
check() {  # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "     want: $2"; echo "     got:  $3"; fails=$((fails + 1)); fi
}

# Four workspaces sharing one state home.
for w in a b c d; do mkdir -p "$TMP/$w"; cp -R "$SRC" "$TMP/$w/workspace-dev"; done
dev_eval() {  # workspace code: bin/dev's functions, sourced from that workspace
  ( DEV_HOME="$TMP/home"; source "$TMP/$1/workspace-dev/bin/dev" >/dev/null 2>&1; eval "$2" ) 2>&1
}

check "services are ports.txt minus containers" "api web" "$(dev_eval a 'echo $APP_SERVICES')"
check "slot 2 ports" "8120 4120 25452 18120" \
  "$(dev_eval a 'set_slot_env 2; echo $PORT_API $PORT_WEB $PORT_POSTGRES $PC_PORT')"

check "first workspace gets slot 0" 0 "$(dev_eval a slot_claim)"
check "same workspace keeps its slot" 0 "$(dev_eval a slot_claim)"
check "second workspace gets slot 1" 1 "$(dev_eval b slot_claim)"
dev_eval c slot_claim >/dev/null
out=$(dev_eval d slot_claim)
case "$out" in *"all 3 slots are in use"*) echo "ok   fourth workspace is refused" ;;
  *) echo "FAIL fourth workspace is refused"; echo "     got: $out"; fails=$((fails + 1)) ;; esac
rm -rf "$TMP/b"
check "a deleted workspace's slot is reclaimed" 1 "$(dev_eval d slot_claim)"

check "doctor reads keys + reasons from secrets.env.example" \
  "missing|example: the (pretend) LLM feature fails without it" \
  "$(dev_eval a 'unset EXAMPLE_API_KEY; JSON=1 cmd_doctor' | jq -r '.[] | select(.name == "secret:EXAMPLE_API_KEY") | "\(.status)|\(.detail)"')"
check "process env satisfies a secret" ok \
  "$(dev_eval a 'export EXAMPLE_API_KEY=x; JSON=1 cmd_doctor' | jq -r '.[] | select(.name == "secret:EXAMPLE_API_KEY") | .status')"

# `dev up` on a running stack: api already runs (process-compose refuses to start it
# again), web is new. Fakes on PATH: a no-op mise (so the real toolchain stays out),
# a docker that's "running", and a process-compose that records what gets started.
FAKE=$TMP/bin; mkdir -p "$FAKE"; export STARTED=$TMP/started
printf '#!/bin/sh\n' >"$FAKE/mise"; printf '#!/bin/sh\nexit 0\n' >"$FAKE/docker"
cat >"$FAKE/process-compose" <<'EOF'
#!/bin/sh
case "$*" in
  *"project state"*) exit 0 ;;
  *"process list"*) web=Disabled; grep -q web "$STARTED" 2>/dev/null && web=Running
    echo "[{\"name\":\"api\",\"status\":\"Running\",\"is_ready\":\"Ready\",\"has_ready_probe\":true,\"exit_code\":0},
           {\"name\":\"web\",\"status\":\"$web\",\"is_ready\":\"Ready\",\"has_ready_probe\":true,\"exit_code\":0}]" ;;
  *"process start api"*) echo "process api is already running" >&2; exit 1 ;;
  *"process start "*) echo "$*" | grep -o 'start .*' >>"$STARTED" ;;
esac
EOF
chmod +x "$FAKE"/*
out=$(PATH="$FAKE:$PATH" DEV_HOME="$TMP/home-up" bash "$TMP/a/workspace-dev/bin/dev" up api web 2>&1)
check "up on a running stack succeeds" 0 "$?"
check "up starts only the services not yet running" "start web" "$(cat "$STARTED" 2>/dev/null)"

echo; [ $fails = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
