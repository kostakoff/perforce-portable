#!/bin/bash
#
# P4 Server (p4d) maintenance script (macOS version)
#
# Creates a checkpoint of the P4 Server and cleans up old
# checkpoints and journals.
#
# Usage: p4d-maintenance.sh [options]
#

###############################################################################
# Global Config
CLEANUP_DAYS=14
MINIMUM_JNLS=14
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P4D="$SCRIPT_DIR/p4d"

SRV_DIR=""
MODE="all"

usage() {
    cat <<EOS

Usage: p4d-maintenance.sh [options]

    -r <server-dir>   - Server directory (default: ..)
                        Contains: root/, journals/, logs/, archives/
    --checkpoint-only - Only create checkpoint, skip cleanup
    --cleanup-only    - Only cleanup old files, skip checkpoint
    --days <N>        - Delete files older than N days (default: 14)
    -h                - Show this help

EOS
}

log() {
    local msg="$1"
    local logfile="$2"
    echo "$(date '+%Y-%m-%dT%H:%M:%S'): $msg"
    [ -n "$logfile" ] && echo "$(date '+%Y-%m-%dT%H:%M:%S'): $msg" >> "$logfile"
}

#-------------------------------------------------------------------------------
# Parse arguments
#-------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        -r)                SRV_DIR=$2; shift 2;;
        --checkpoint-only) MODE="checkpoint"; shift;;
        --cleanup-only)    MODE="cleanup"; shift;;
        --days)            CLEANUP_DAYS=$2; shift 2;;
        -h|--help)         usage; exit 0;;
        *)                 echo "Unknown option: $1"; usage; exit 1;;
    esac
done

# Resolve server directory
if [ -z "$SRV_DIR" ]; then
    SRV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

if [ ! -d "$SRV_DIR" ]; then
    echo "Error: Server directory not found: $SRV_DIR"
    exit 1
fi

SRV_DIR="$(cd "$SRV_DIR" && pwd)"
P4ROOT="$SRV_DIR/root"
JNL_DIR="$SRV_DIR/journals"
LOG_DIR="$SRV_DIR/logs"
LOGFILE="$JNL_DIR/maintenance.log"

if [ ! -d "$P4ROOT" ]; then
    echo "Error: P4ROOT not found: $P4ROOT (run setup-p4d.sh first)"
    exit 1
fi

[ -x "$P4D" ] || { echo "Error: p4d not found: $P4D"; exit 1; }

# Check if journalPrefix is configured
JNL_PREFIX=""
if out=$("$P4D" -r "$P4ROOT" "-cshow thisserver" 2>/dev/null | grep "^journalPrefix = "); then
    JNL_PREFIX=$(echo "$out" | awk '{print $3}')
    JNL_PREFIX=$(basename "$JNL_PREFIX")
else
    JNL_PREFIX=""
fi

#-------------------------------------------------------------------------------
# Checkpoint
#-------------------------------------------------------------------------------
checkpoint() {
    log "Beginning checkpoint..." "$LOGFILE"

    # Get current journal counter from db.counters dump
    # Format: @pv@ 1 @db.counters@ @journal@ @N@
    local rjnl
    rjnl=$("$P4D" -r "$P4ROOT" -jd - db.counters 2>/dev/null | grep '@journal@' | grep -o '@[0-9]*@$' | tr -d '@')
    if [ -z "$rjnl" ]; then
        rjnl=0
    fi

    # Create checkpoint (p4d -jd doesn't auto-gzip, so gzip manually)
    local ckp_base ckp_name
    if [ -n "$JNL_PREFIX" ]; then
        ckp_base="$JNL_DIR/${JNL_PREFIX}.ckp.$rjnl"
    else
        ckp_base="$JNL_DIR/checkpoint.$rjnl"
    fi

    local tmp_ckpt="$ckp_base.tmp"
    local out
    out=$("$P4D" -r "$P4ROOT" -jd "$tmp_ckpt" 2>&1)
    if [ $? -ne 0 ]; then
        log "ERROR: Checkpoint failed: $out" "$LOGFILE"
        rm -f "$tmp_ckpt"
        return 1
    fi

    gzip -f "$tmp_ckpt"
    mv "$tmp_ckpt.gz" "$ckp_base.gz"
    ckp_name="$ckp_base.gz"

    # p4d -jd auto-creates a .md5 file alongside the checkpoint; move it
    if [ -f "$tmp_ckpt.md5" ]; then
        mv "$tmp_ckpt.md5" "$ckp_base.md5"
    fi

    log "Checkpoint created: $ckp_name" "$LOGFILE"

    # Verify with md5 (macOS: md5 -q)
    # p4d writes .md5 as "MD5 (filename) = HASH" — extract just the hash
    local md5_file="$ckp_base.md5"
    if [ -f "$ckp_name" ] && [ -f "$md5_file" ]; then
        local md5_calc md5_test
        md5_calc=$(gunzip -c "$ckp_name" | md5 -q | tr '[:upper:]' '[:lower:]')
        md5_test=$(sed 's/.*= //' "$md5_file" | tr '[:upper:]' '[:lower:]')
        if [ "$md5_calc" = "$md5_test" ]; then
            log "Checkpoint checksum verified" "$LOGFILE"
        else
            log "WARNING: Checkpoint checksum mismatch! ($md5_calc vs $md5_test)" "$LOGFILE"
        fi
    fi

    log "Checkpoint complete" "$LOGFILE"
    return 0
}

#-------------------------------------------------------------------------------
# Cleanup
#-------------------------------------------------------------------------------
cleanup() {
    log "Beginning cleanup (files older than $CLEANUP_DAYS days)..." "$LOGFILE"

    local delcount=0
    local allcount oldcount cleanupdays=$CLEANUP_DAYS

    if [ -n "$JNL_PREFIX" ]; then
        allcount=$(find "$JNL_DIR" -name "${JNL_PREFIX}.ckp.*.gz" 2>/dev/null | wc -l | tr -d ' ')
        oldcount=$(find "$JNL_DIR" -mtime "+$cleanupdays" -name "${JNL_PREFIX}.ckp.*.gz" 2>/dev/null | wc -l | tr -d ' ')
    else
        allcount=$(find "$JNL_DIR" -name "checkpoint.*.gz" 2>/dev/null | wc -l | tr -d ' ')
        oldcount=$(find "$JNL_DIR" -mtime "+$cleanupdays" -name "checkpoint.*.gz" 2>/dev/null | wc -l | tr -d ' ')
    fi

    delcount=$((allcount - oldcount))

    # Ensure we keep at least MINIMUM_JNLS checkpoints
    while [ "$oldcount" -gt 0 ] && [ "$delcount" -lt "$MINIMUM_JNLS" ]; do
        cleanupdays=$((cleanupdays + 1))
        if [ -n "$JNL_PREFIX" ]; then
            oldcount=$(find "$JNL_DIR" -mtime "+$cleanupdays" -name "${JNL_PREFIX}.ckp.*.gz" 2>/dev/null | wc -l | tr -d ' ')
        else
            oldcount=$(find "$JNL_DIR" -mtime "+$cleanupdays" -name "checkpoint.*.gz" 2>/dev/null | wc -l | tr -d ' ')
        fi
        delcount=$((allcount - oldcount))
    done

    # Delete old files
    if [ "$oldcount" -gt 0 ]; then
        if [ -n "$JNL_PREFIX" ]; then
            find "$JNL_DIR" -mtime "+$cleanupdays" \( -name "${JNL_PREFIX}.ckp.*" -o -name "${JNL_PREFIX}.jnl.*" \) -exec rm -f {} + 2>/dev/null
        else
            find "$JNL_DIR" -mtime "+$cleanupdays" \( -name "checkpoint.*" -o -name "journal.*" \) -exec rm -f {} + 2>/dev/null
        fi
        log "Removed old checkpoint/journal files (older than $cleanupdays days)" "$LOGFILE"
    else
        log "No old files to clean up" "$LOGFILE"
    fi

    log "Cleanup complete" "$LOGFILE"
    return 0
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
case "$MODE" in
    checkpoint)
        checkpoint
        ;;
    cleanup)
        cleanup
        ;;
    all)
        checkpoint && cleanup
        ;;
esac
