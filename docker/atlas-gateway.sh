#!/bin/bash
# atlas-gateway.sh — the container CMD (see Dockerfile). Runs by the time
# main-wrapper.sh has activated the venv and dropped to the hermes user,
# so `hermes` is on PATH and $HOME is /opt/data.
#
# Two jobs, both restoring the battle-tested pre-s6 deployment semantics:
#
# 1. Foreground gateway, not s6-supervised. Hermes 0.16's `gateway run`
#    detects the s6 container and hands off to a supervised slot
#    (gateway-default) whose s6-log writes to /opt/data/logs/gateways/ —
#    nothing reaches container stdout, so Railway's log stream goes dark
#    after the boot banner and a crashed gateway is silently restarted out
#    of sight. HERMES_GATEWAY_NO_SUPERVISE=1 (documented by the delegation
#    banner itself) opts out: the gateway runs in this process, `-v` puts
#    INFO on stderr, Railway captures it, and a gateway death exits the
#    container so Railway's ON_FAILURE policy restarts it *visibly*.
#
# 2. SIGTERM exit-code translation. Hermes deliberately exits 1 on
#    signal-initiated shutdown ("so systemd Restart=on-failure can revive
#    the gateway"), and Railway treats any non-zero exit as a crash —
#    firing a "Deploy Crashed!" email on every routine redeploy. Record
#    whether we saw SIGTERM/SIGINT and translate only that exit to 0;
#    a real startup failure or mid-run crash still propagates non-zero.
#    (During container shutdown s6 signals all remaining processes, so
#    hermes receives SIGTERM directly; our trap is just bookkeeping —
#    same mechanics as the tini -g era.)

export HERMES_GATEWAY_NO_SUPERVISE=1

set +e
RECEIVED_TERM=0
trap 'RECEIVED_TERM=1' SIGTERM SIGINT
hermes gateway run -v
EXIT_CODE=$?
echo "[atlas-gateway] hermes exited code=$EXIT_CODE received_term=$RECEIVED_TERM" >&2
if [ "$RECEIVED_TERM" = "1" ]; then
    exit 0
fi
exit "$EXIT_CODE"
