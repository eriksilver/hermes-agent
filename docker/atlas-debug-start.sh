#!/bin/bash
# Diagnostic wrapper for Atlas-on-Railway debug. Prints env + paths before
# invoking the real entrypoint, with stderr merged into stdout so Hermes
# error messages aren't lost in Railway's log split.
set -x  # trace each command

echo "==== ENV CHECK ===="
echo "PATH=$PATH"
echo "HERMES_HOME=$HERMES_HOME"
echo "USER=$(whoami)"
echo "PWD=$(pwd)"
echo "TTY=$(tty 2>&1)"
echo
echo "==== HERMES BINARY ===="
ls -la /opt/hermes/.venv/bin/hermes 2>&1 || echo "NOT FOUND"
echo
echo "==== EXPECTED ENV VARS (names only) ===="
env | grep -E "^(SLACK_|ANTHROPIC_|SUPABASE_|VERCEL_|HERMES_)" | sed 's/=.*//' | sort
echo
echo "==== HEAD OF /opt/data ===="
ls /opt/data/ 2>&1 | head -20
echo
echo "==== INVOKE ENTRYPOINT ===="
exec /opt/hermes/docker/entrypoint.sh gateway run 2>&1
