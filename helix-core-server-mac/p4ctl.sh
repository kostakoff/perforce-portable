#!/bin/bash
#
# P4 Server control script (macOS)
#
# Usage: p4ctl.sh <start|stop|restart|status> [server-dir] [port]
#
#   server-dir  — path to p4server/ (default: ..)
#   port        — P4PORT (default: 0.0.0.0:1666)
#
# Stop uses 'p4 admin stop' (graceful)
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P4D="$SCRIPT_DIR/p4d"
P4="$SCRIPT_DIR/p4"

# Load credentials from .p4config in parent directory
P4CONFIG="${SCRIPT_DIR}/../.p4config"
CFG_USER=""
CFG_PASSWD=""
CFG_PORT_NUM=""
if [ -f "$P4CONFIG" ]; then
    CFG_USER=$(grep '^P4USER=' "$P4CONFIG" | head -1 | cut -d= -f2-)
    CFG_PASSWD=$(grep '^P4PASSWD=' "$P4CONFIG" | head -1 | cut -d= -f2-)
    CFG_PORT_NUM=$(grep '^P4PORT=' "$P4CONFIG" | head -1 | sed 's/.*://')
fi

P4_USER_OPT=""
[ -n "$CFG_USER" ] && P4_USER_OPT="-u$CFG_USER"

usage() {
    cat <<EOS

Usage: p4ctl.sh <start|stop|restart|status> [server-dir] [port]

  Commands:
    start    — start p4d daemon
    stop     — graceful shutdown (p4 admin stop)
    restart  — stop + start
    status   — show server status

  Arguments:
    server-dir  — path to p4server/ (default: ..)
    port        — P4PORT (default: 0.0.0.0:1666)

EOS
}

# Resolve server directory
CMD="${1:-}"
SRV_DIR="${2:-$(cd "$SCRIPT_DIR/.." && pwd)}"
P4PORT="${3:-0.0.0.0:${CFG_PORT_NUM:-1666}}"

if [ -d "$SRV_DIR" ]; then
    SRV_DIR="$(cd "$SRV_DIR" && pwd)"
fi
P4ROOT="$SRV_DIR/root"
JNL_DIR="$SRV_DIR/journals"
LOG_DIR="$SRV_DIR/logs"

# Extract port number for p4 client connection
P4PORT_NUM=$(echo "$P4PORT" | sed 's/.*://')
P4_LOCAL="127.0.0.1:$P4PORT_NUM"

is_running() {
    pgrep -x p4d >/dev/null 2>&1
}

do_start() {
    if is_running; then
        echo "p4d is already running (pid $(pgrep -x p4d))"
        return 0
    fi
    if [ ! -d "$P4ROOT" ]; then
        echo "error: P4ROOT not found: $P4ROOT" >&2
        echo "Run setup-p4d.sh first." >&2
        return 1
    fi
    echo "Starting p4d: P4ROOT=$P4ROOT P4PORT=$P4PORT"
    "$P4D" \
        -r "$P4ROOT" \
        -p "$P4PORT" \
        -L "$LOG_DIR/log" \
        -J "$JNL_DIR/journal" \
        -d
}

do_stop() {
    if ! is_running; then
        echo "p4d is not running"
        return 0
    fi
    echo "Stopping p4d (graceful)..."
    # Authenticate using credentials from .p4config (admin stop requires auth)
    if [ -n "$CFG_USER" ] && [ -n "$CFG_PASSWD" ]; then
        echo "$CFG_PASSWD" | "$P4" -C none -p"$P4_LOCAL" $P4_USER_OPT login >/dev/null 2>&1
    fi
    # Graceful shutdown releases file locks properly
    if "$P4" -C none -p"$P4_LOCAL" $P4_USER_OPT admin stop >/dev/null 2>&1; then
        for i in $(seq 1 10); do
            is_running || { echo "p4d stopped"; return 0; }
            sleep 0.5
        done
    fi
    # Fallback: SIGTERM
    echo "Graceful stop unavailable, sending SIGTERM..."
    pkill p4d
    sleep 1
    if is_running; then
        echo "Sending SIGKILL..."
        pkill -9 p4d
        sleep 1
    fi
    is_running && { echo "error: failed to stop p4d" >&2; return 1; }
    echo "Waiting for file locks to clear..."
    sleep 3
    echo "p4d stopped"
}

do_status() {
    if is_running; then
        local pid
        pid=$(pgrep -x p4d)
        echo "p4d is running (pid $pid)"
        "$P4" -C none -p"$P4_LOCAL" $P4_USER_OPT info 2>/dev/null | grep -E 'Server root|Server address|Server date|Server uptime|User name'
    else
        echo "p4d is not running"
    fi
}

case "$CMD" in
    start)   do_start;;
    stop)    do_stop;;
    restart) do_stop && sleep 1 && do_start;;
    status)  do_status;;
    *)       usage; exit 1;;
esac
