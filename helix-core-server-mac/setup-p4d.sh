#!/bin/bash
# vim:sw=4:ts=4:et:
#-------------------------------------------------------------------------------
# Configuration script for P4 Server (macOS version)
#
# Synopsis:
#
#    setup-p4d.sh [options]
#
#    Options:
#
#    -n                     - Non-interactive mode (use flags below)
#    -p <P4PORT>            - P4 Server address (default: 0.0.0.0:1666)
#    -r <server-dir>        - Server directory (default: ..)
#                             Contains: root/, journals/, logs/, archives/
#    -u <username>          - Super-user login name (default: super)
#    -P <password>          - Super-user password (required in non-interactive)
#    --unicode              - Enable unicode mode
#    --case <0|1>           - Case-sensitivity: 0=sensitive, 1=insensitive [default]
#    -h --help              - Show help
#
#-------------------------------------------------------------------------------

trap 'stty echo 2>/dev/null; exit 1' INT TERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P4D="$SCRIPT_DIR/p4d"
P4="$SCRIPT_DIR/p4"

# Defaults
INTERACTIVE=true
UNICODE=n
CASE=1
P4PORT="0.0.0.0:1666"
SRV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
P4USER="super"
P4PASSWD=""

#-------------------------------------------------------------------------------
# Output helpers
#-------------------------------------------------------------------------------
highlight() { echo -e "\033[32m$1\033[0m"; }
error()     { echo -e "\033[31m$1\033[0m" >&2; }

die() {
    error "FATAL: $*"
    exit 1
}

usage() {
    cat <<EOS

Usage: setup-p4d.sh [options]

    -n                - Non-interactive mode (all values from flags)
    -p <P4PORT>       - P4 Server address (default: 0.0.0.0:1666)
    -r <server-dir>   - Server directory (default: ..)
                        Contains: root/, journals/, logs/, archives/
    -u <username>     - Super-user login name (default: super)
    -P <password>     - Super-user password (required in non-interactive mode)
    --unicode         - Enable unicode mode on server
    --case <0|1>      - Case-sensitivity: 0=sensitive, 1=insensitive [default]
    -h --help         - Display this help and exit

EOS
}

#-------------------------------------------------------------------------------
# Password validation
#-------------------------------------------------------------------------------
LAST_PASS=""

strong_password() {
    local pw=$1
    if [ ${#pw} -ge 8 ]; then
        if echo "$pw" | grep -q '[[:upper:]]' && echo "$pw" | grep -q '[[:lower:]]'; then
            return 0
        elif echo "$pw" | grep -q '[[:upper:]]' && echo "$pw" | grep -q '[^[:alpha:]]'; then
            return 0
        elif echo "$pw" | grep -q '[[:lower:]]' && echo "$pw" | grep -q '[^[:alpha:]]'; then
            return 0
        fi
    fi
    return 1
}

validate_password() {
    local pw=$1
    if [ "$LAST_PASS" != "" ]; then
        if [ "$LAST_PASS" != "$pw" ]; then
            error "Passwords do not match."
            LAST_PASS=""
            return 1
        else
            LAST_PASS=""
            return 0
        fi
    fi
    if ! strong_password "$pw"; then
        error "Passwords must be at least 8 characters with at least two of: upper, lower, non-alpha."
        return 1
    fi
    LAST_PASS="$pw"
    echo "Re-enter password."
    return 1
}

validate_username() {
    local user=$1
    [ -z "$user" ] && return 1
    echo "$user" | grep -q '^[0-9]' && { error "Usernames must not begin with numbers."; return 1; }
    return 0
}

check_bool_response() {
    local r=$1
    case "$r" in y|Y|yes|true|0|n|N|no|false|1) return 0;; esac
    return 1
}

promptfor() {
    local var="$1" prompt="$2" secure=${3:-false} default_value="${4:-}" check_func="${5:-true}"
    [ -n "$default_value" ] && prompt="$prompt [$default_value]"
    while true; do
        local pw=""
        $secure && stty -echo 2>/dev/null
        read -r -p "$prompt: " pw
        $secure && stty echo 2>/dev/null
        [ -z "$pw" ] && [ -n "$default_value" ] && pw=$default_value
        if $check_func "$pw"; then
            eval "$var=\"$pw\""
            break
        fi
    done
}

#-------------------------------------------------------------------------------
# Parse arguments
#-------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)      usage; exit 0;;
        -n)             INTERACTIVE=false; shift;;
        -p)             P4PORT=$2; shift 2;;
        -r)             SRV_DIR=$2; shift 2;;
        -u)             P4USER=$2; shift 2;;
        -P)             P4PASSWD=$2; shift 2;;
        --unicode)      UNICODE=y; shift;;
        --case)         CASE=$2; shift 2;;
        *)              die "Unknown option: $1";;
    esac
done

#-------------------------------------------------------------------------------
# Interactive prompts
#-------------------------------------------------------------------------------
if $INTERACTIVE; then
    highlight "\nP4 Server setup (macOS)\n"
    promptfor SRV_DIR  "Server directory"                false "$SRV_DIR"
    promptfor P4PORT   "P4 Server address (P4PORT)"     false "$P4PORT"
    promptfor P4USER   "Super-user login"               false "$P4USER" validate_username
    promptfor P4PASSWD "Super-user password"            true  ""        validate_password
fi

# Validate
[ -z "$SRV_DIR" ]  && die "Server directory is required"
[ -z "$P4PORT" ]   && die "P4PORT is required"
[ -z "$P4USER" ]   && die "P4USER is required"
[ -z "$P4PASSWD" ] && die "P4PASSWD is required (use -P or interactive mode)"
strong_password "$P4PASSWD" || die "Password too weak (need 8+ chars, 2 char classes)"
validate_username "$P4USER" || die "Invalid username"

# Resolve server directory to absolute
mkdir -p "$SRV_DIR"
SRV_DIR="$(cd "$SRV_DIR" && pwd)"
P4ROOT="$SRV_DIR/root"
JNL_DIR="$SRV_DIR/journals"
LOG_DIR="$SRV_DIR/logs"

# Check binaries exist
[ -x "$P4D" ] || die "p4d binary not found: $P4D"
[ -x "$P4" ]  || die "p4 binary not found: $P4"

# Check if already initialized
if [ -f "$P4ROOT/db.counters" ]; then
    error "Server at $SRV_DIR already contains database files."
    error "Delete the directory first for a fresh install, or use p4d-maintenance.sh for upkeep."
    exit 1
fi

#-------------------------------------------------------------------------------
# Create directory structure
#-------------------------------------------------------------------------------
highlight "\nCreating directory structure in $SRV_DIR ..."
mkdir -p "$P4ROOT" "$JNL_DIR" "$LOG_DIR" "$SRV_DIR/archives"

#-------------------------------------------------------------------------------
# Initialize database
#-------------------------------------------------------------------------------
highlight "Initializing database in $P4ROOT ..."

"$P4D" -r "$P4ROOT" -C "$CASE" \
    -L "$LOG_DIR/log" \
    -J "$JNL_DIR/journal" \
    "-cset P4JOURNAL=$JNL_DIR/journal" >/dev/null

"$P4D" -r "$P4ROOT" "-cset P4LOG=$LOG_DIR/log" >/dev/null

# Store P4PORT in server config
"$P4D" -r "$P4ROOT" "-cset P4PORT=$P4PORT" >/dev/null

#-------------------------------------------------------------------------------
# Start p4d daemon
#-------------------------------------------------------------------------------
highlight "Starting p4d on $P4PORT ..."
"$P4D" -r "$P4ROOT" -C "$CASE" \
    -L "$LOG_DIR/log" \
    -J "$JNL_DIR/journal" \
    -p "$P4PORT" \
    -d

# Wait for server to accept connections
P4_CMD="$P4 -C none -p$P4PORT -u$P4USER"
attempts=0
while ! $P4_CMD info >/dev/null 2>&1; do
    sleep 1
    attempts=$((attempts + 1))
    if [ $attempts -gt 15 ]; then
        die "Server failed to start! Check $LOG_DIR/log for details."
    fi
done

highlight "Server is up."

#-------------------------------------------------------------------------------
# Initialize repository (user, password, protections, configurables)
#-------------------------------------------------------------------------------
highlight "Creating super-user account '$P4USER'..."
$P4_CMD user -o 2>/dev/null | $P4_CMD user -i 2>/dev/null || true

highlight "Setting password..."
$P4_CMD passwd >/dev/null <<EOF
$P4PASSWD
$P4PASSWD
EOF

highlight "Creating login ticket..."
$P4_CMD login >/dev/null <<EOF
$P4PASSWD
EOF

highlight "Initializing protections table..."
$P4_CMD protect -o | awk '/^\twrite user/ { print; print "\tlist user * * -//spec/..."; next } { print }' | $P4_CMD protect -i

highlight "Setting security level..."
$P4_CMD counter -f security 4

#-------------------------------------------------------------------------------
# Server configurables
#-------------------------------------------------------------------------------
highlight "Setting server configurables..."

$P4_CMD configure set run.users.authorize=1        >/dev/null 2>&1 || true
$P4_CMD configure set dm.user.noautocreate=2        >/dev/null 2>&1 || true
$P4_CMD configure set dm.user.resetpassword=1       >/dev/null 2>&1 || true
$P4_CMD configure set dm.info.hide=1                >/dev/null 2>&1 || true
$P4_CMD configure set dm.user.hideinvalid=1         >/dev/null 2>&1 || true
$P4_CMD configure set server.start.unlicensed=1     >/dev/null 2>&1 || true

$P4_CMD configure set server.maxcommands=2500       >/dev/null 2>&1 || true
$P4_CMD configure set net.backlog=2048              >/dev/null 2>&1 || true
$P4_CMD configure set net.autotune=1                >/dev/null 2>&1 || true
$P4_CMD configure set db.monitor.shared=4096        >/dev/null 2>&1 || true
$P4_CMD configure set db.reorg.disable=1            >/dev/null 2>&1 || true
$P4_CMD configure set lbr.autocompress=1            >/dev/null 2>&1 || true

$P4_CMD configure set filesys.bufsize=1M            >/dev/null 2>&1 || true
$P4_CMD configure set filesys.checklinks=2          >/dev/null 2>&1 || true
$P4_CMD configure set server.commandlimits=2        >/dev/null 2>&1 || true

$P4_CMD configure set rpl.checksum.auto=1           >/dev/null 2>&1 || true
$P4_CMD configure set rpl.checksum.change=2         >/dev/null 2>&1 || true
$P4_CMD configure set rpl.checksum.table=1          >/dev/null 2>&1 || true

$P4_CMD configure set monitor=1                     >/dev/null 2>&1 || true
$P4_CMD configure set server=3                      >/dev/null 2>&1 || true

$P4_CMD configure set filesys.P4ROOT.min=2G         >/dev/null 2>&1 || true
$P4_CMD configure set filesys.depot.min=2G          >/dev/null 2>&1 || true
$P4_CMD configure set filesys.P4JOURNAL.min=2G      >/dev/null 2>&1 || true

# Structured logs
$P4_CMD configure set serverlog.file.1="$LOG_DIR/commands.csv"  >/dev/null 2>&1 || true
$P4_CMD configure set serverlog.retain.1=10         >/dev/null 2>&1 || true
$P4_CMD configure set serverlog.file.2="$LOG_DIR/errors.csv"    >/dev/null 2>&1 || true
$P4_CMD configure set serverlog.retain.2=10         >/dev/null 2>&1 || true
$P4_CMD configure set serverlog.file.3="$LOG_DIR/events.csv"    >/dev/null 2>&1 || true
$P4_CMD configure set serverlog.retain.3=10         >/dev/null 2>&1 || true
$P4_CMD configure set serverlog.file.4="$LOG_DIR/integrity.csv" >/dev/null 2>&1 || true
$P4_CMD configure set serverlog.retain.4=10         >/dev/null 2>&1 || true
$P4_CMD configure set serverlog.file.5="$LOG_DIR/auth.csv"      >/dev/null 2>&1 || true
$P4_CMD configure set serverlog.retain.5=10         >/dev/null 2>&1 || true

#-------------------------------------------------------------------------------
# Depots
#-------------------------------------------------------------------------------
highlight "Creating spec and unload depots..."
$P4_CMD depot -o -t spec spec     | $P4_CMD depot -i >/dev/null 2>&1 || true
$P4_CMD admin updatespecdepot -a  >/dev/null 2>&1 || true
$P4_CMD depot -o -t unload unload | $P4_CMD depot -i >/dev/null 2>&1 || true

#-------------------------------------------------------------------------------
# Server spec + server.id
#-------------------------------------------------------------------------------
highlight "Creating server spec..."
echo "master" > "$P4ROOT/server.id"
$P4_CMD server -i >/dev/null 2>&1 <<EOF || true
ServerID: master
Type: server
Services: commit-server
Address: $P4PORT
Description: Created by setup-p4d.sh
EOF

#-------------------------------------------------------------------------------
# Typemap
#-------------------------------------------------------------------------------
highlight "Populating typemap..."
$P4_CMD typemap -i >/dev/null 2>&1 <<'EOF' || true
TypeMap:
	text //....asp
	text //....cnf
	text //....css
	text //....htm
	text //....html
	text //....inc
	text //....js
	text+w //....log
	text+w //....ini
	text+w //....pdm
	binary+Fl //....zip
	binary+Fl //....bz2
	binary+Fl //....rar
	binary+Fl //....gz
	binary+Fl //....avi
	binary+Fl //....jpg
	binary+Fl //....jpeg
	binary+Fl //....mpg
	binary+Fl //....gif
	binary+Fl //....tif
	binary+Fl //....mov
	binary+Fl //....jar
	binary+l //....ico
	binary+l //....exp
	binary+l //....btr
	binary+l //....bmp
	binary+l //....doc
	binary+l //....dot
	binary+l //....xls
	binary+l //....ppt
	binary+l //....pdf
	binary+l //....tar
	binary+l //....exe
	binary+l //....dll
	binary+l //....lib
	binary+l //....bin
	binary+l //....class
	binary+l //....war
	binary+l //....ear
	binary+l //....so
	binary+l //....rpt
	binary+l //....cfm
	binary+l //....ma
	binary+l //....mb
	binary+l //....pac
	binary+l //....m4a
	binary+l //....mp4
	binary+l //....aac
	binary+l //....wma
	binary+l //....docx
	binary+l //....pptx
	binary+l //....xlsx
	binary+l //....png
	binary+l //....raw
	binary+l //....odt
	binary+l //....ods
	binary+l //....odg
	binary+l //....odp
	binary+l //....otg
	binary+l //....ots
	binary+l //....ott
	binary+l //....psd
	binary+l //....sxw
EOF

#-------------------------------------------------------------------------------
# Generate .p4config
#-------------------------------------------------------------------------------
highlight "Generating .p4config..."
P4PORT_NUM=$(echo "$P4PORT" | sed 's/.*://')
cat > "$SRV_DIR/.p4config" <<EOF
# P4 client configuration
# Copy this file to your project root and edit as needed.
# Activate with: p4 set P4CONFIG=.p4config
P4PORT=127.0.0.1:$P4PORT_NUM
P4USER=$P4USER
P4PASSWD=$P4PASSWD
P4CHARSET=utf8
EOF

#-------------------------------------------------------------------------------
# Done
#-------------------------------------------------------------------------------
highlightOn() { echo -e "\033[32m"; }
highlightOff() { echo -e "\033[0m"; }

highlightOn
cat <<EOF

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::
::  P4 Server setup complete!
::
::  Server dir:  $SRV_DIR
::  P4ROOT:      $P4ROOT
::  P4PORT:      $P4PORT
::  User:        $P4USER
::
::  Config file: $SRV_DIR/.p4config
::  Copy it to your project root and activate:
::
::      p4 set P4CONFIG=.p4config
::
::  Then just run 'p4' from the project directory.
::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

EOF
highlightOff
