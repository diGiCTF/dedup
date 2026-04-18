#!/usr/bin/env bash
set -euo pipefail

PROG="$(basename "$0")"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dedup"
CONFIG_FILE="$CONFIG_DIR/config"
DEFAULT_CASE="lower"

usage() {
    cat <<EOF
Usage: $PROG [options] <new_wordlist | ->
       $PROG -l [<name>] [-d <dir>]
       $PROG -p
       $PROG --set-path <dir>
       $PROG --normalize [<name>] [--case <mode>] [--force-case]

Maintain a per-reference master wordlist and emit only words not previously seen.

  -m, --master <name>   Reference namespace (default: "default")
  -d, --dir <path>      Directory for master/filtered files. Overrides the
                        resolved default for this invocation only.
  -l, --locate [name]   Print master path for <name>, or list all namespaces
                        in <dir> when no name given.
  -p, --path            Print the currently resolved dedup directory and exit.
  --set-path <dir>      Persist <dir> as the default dedup directory.
  --case <mode>         Case mode for normalization. One of:
                          lower    (default) — tolower the whole line
                          upper              — toupper the whole line
                          proper             — tolower, uppercase first char
                          preserve           — keep as-is (case-sensitive)
  -L / -U / -P / -K     Short toggles for --case lower|upper|proper|preserve
  --force-case          Override the case mode recorded in the namespace's
                        metadata (otherwise mismatches are rejected).
  --normalize [name]    Rewrite the master for <name> using its recorded case
                        (or --case if given). Dedups after transform.
  -q, --quiet           Suppress summary output
  -h, --help            Show this help

Resolution order for the dedup directory:
  1. -d <dir>              (per-invocation override)
  2. \$DEDUP_DIR             (environment)
  3. config file           ($CONFIG_FILE)
  4. current directory     (last resort)

Case behavior:
  The first time a namespace is written, its case mode is recorded in
  <dir>/dedup_<name>_master.meta. Subsequent runs must match that mode
  (use --force-case to override, or --normalize to rewrite).

Reads from stdin if <new_wordlist> is "-".
Files produced:
  <dir>/dedup_<name>_master.txt
  <dir>/dedup_<name>_filtered.txt
  <dir>/dedup_<name>_master.meta
EOF
}

valid_case() {
    case "$1" in lower|upper|proper|preserve) return 0 ;; *) return 1 ;; esac
}

read_config_dir() {
    [[ -f "$CONFIG_FILE" ]] || return 1
    local line val
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^[[:space:]]*DEDUP_DIR[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            val="${BASH_REMATCH[1]}"
            val="${val%\"}"; val="${val#\"}"
            val="${val%\'}"; val="${val#\'}"
            [[ -n "$val" ]] && { printf '%s\n' "$val"; return 0; }
        fi
    done < "$CONFIG_FILE"
    return 1
}

write_config_dir() {
    local new_dir="$1"
    mkdir -p "$CONFIG_DIR" "$new_dir"
    local tmp
    tmp="$(mktemp "$CONFIG_DIR/config.XXXXXX")"
    {
        echo "# dedup config — managed by 'dedup --set-path'. Edit freely."
        echo "DEDUP_DIR=$new_dir"
    } > "$tmp"
    mv -- "$tmp" "$CONFIG_FILE"
    echo "Saved: DEDUP_DIR=$new_dir → $CONFIG_FILE"
}

read_meta_case() {
    local meta="$1" line val
    [[ -f "$meta" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^[[:space:]]*case[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            val="${BASH_REMATCH[1]}"
            val="${val%%[[:space:]]*}"
            valid_case "$val" && { printf '%s\n' "$val"; return 0; }
        fi
    done < "$meta"
    return 1
}

write_meta_case() {
    local meta="$1" mode="$2" tmp
    tmp="$(mktemp "${meta%/*}/dedup_meta.XXXXXX")"
    {
        echo "# dedup namespace metadata — written by dedup. Edit carefully."
        echo "case=$mode"
    } > "$tmp"
    mv -- "$tmp" "$meta"
}

DIR_OVERRIDE=""
if [[ -n "${DEDUP_DIR:-}" ]]; then
    DIR_DEFAULT="$DEDUP_DIR"
    DIR_SOURCE="env"
elif DIR_FROM_CONFIG="$(read_config_dir 2>/dev/null)"; then
    DIR_DEFAULT="$DIR_FROM_CONFIG"
    DIR_SOURCE="config"
else
    DIR_DEFAULT="."
    DIR_SOURCE="cwd"
fi

REF="default"
QUIET=0
INPUT=""
LOCATE=0
LOCATE_NAME=""
PRINT_PATH=0
SET_PATH=""
CASE_FLAG=""
FORCE_CASE=0
NORMALIZE=0
NORMALIZE_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--master) REF="${2:?missing value for $1}"; shift 2 ;;
        -d|--dir)    DIR_OVERRIDE="${2:?missing value for $1}"; shift 2 ;;
        -l|--locate)
            LOCATE=1; shift
            if [[ $# -gt 0 && "$1" != -* ]]; then LOCATE_NAME="$1"; shift; fi
            ;;
        -p|--path)   PRINT_PATH=1; shift ;;
        --set-path)  SET_PATH="${2:?--set-path requires a directory}"; shift 2 ;;
        --case)
            CASE_FLAG="${2:?--case requires a mode}"
            valid_case "$CASE_FLAG" || { echo "Invalid --case value: $CASE_FLAG" >&2; exit 2; }
            shift 2 ;;
        -L) CASE_FLAG="lower"; shift ;;
        -U) CASE_FLAG="upper"; shift ;;
        -P) CASE_FLAG="proper"; shift ;;
        -K) CASE_FLAG="preserve"; shift ;;
        --force-case) FORCE_CASE=1; shift ;;
        --normalize)
            NORMALIZE=1; shift
            if [[ $# -gt 0 && "$1" != -* ]]; then NORMALIZE_NAME="$1"; shift; fi
            ;;
        -q|--quiet)  QUIET=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        --) shift; INPUT="${1:-}"; break ;;
        -)  INPUT="-"; shift ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)  if [[ -z "$INPUT" ]]; then INPUT="$1"; shift; else
                echo "Unexpected argument: $1" >&2; exit 2
            fi ;;
    esac
done

if [[ -n "$SET_PATH" ]]; then
    write_config_dir "$SET_PATH"
    exit 0
fi

DIR="${DIR_OVERRIDE:-$DIR_DEFAULT}"

if [[ "$PRINT_PATH" -eq 1 ]]; then
    if [[ -n "$DIR_OVERRIDE" ]]; then SRC_LABEL="flag"
    else SRC_LABEL="$DIR_SOURCE"; fi
    echo "$DIR"
    echo "(source: $SRC_LABEL)" >&2
    exit 0
fi

AWK_TRANSFORM='
function transform(s, mode,   c) {
    if (mode == "lower")  return tolower(s)
    if (mode == "upper")  return toupper(s)
    if (mode == "proper") {
        if (length(s) == 0) return s
        c = toupper(substr(s,1,1))
        return c tolower(substr(s,2))
    }
    return s
}
'

if [[ "$LOCATE" -eq 1 ]]; then
    if [[ -n "$LOCATE_NAME" ]]; then
        M="$DIR/dedup_${LOCATE_NAME}_master.txt"
        F="$DIR/dedup_${LOCATE_NAME}_filtered.txt"
        if [[ ! -f "$M" ]]; then
            echo "No master found for '$LOCATE_NAME' in $DIR" >&2
            exit 1
        fi
        echo "$M"
        [[ -f "$F" ]] && echo "filtered: $F" >&2
        exit 0
    fi

    if [[ ! -d "$DIR" ]]; then
        echo "Directory not found: $DIR" >&2
        exit 1
    fi
    shopt -s nullglob
    masters=( "$DIR"/dedup_*_master.txt )
    shopt -u nullglob
    if [[ ${#masters[@]} -eq 0 ]]; then
        echo "No namespaces found in $DIR" >&2
        exit 1
    fi
    printf "%-20s  %-8s  %10s  %s\n" "NAMESPACE" "CASE" "LINES" "PATH"
    for m in "${masters[@]}"; do
        base="$(basename "$m")"
        name="${base#dedup_}"
        name="${name%_master.txt}"
        lines=$(wc -l < "$m")
        mode="$(read_meta_case "${m%.txt}.meta" 2>/dev/null || echo '-')"
        printf "%-20s  %-8s  %10d  %s\n" "$name" "$mode" "$lines" "$m"
    done
    exit 0
fi

if [[ "$NORMALIZE" -eq 1 ]]; then
    [[ -n "$NORMALIZE_NAME" ]] || NORMALIZE_NAME="$REF"
    MASTER="$DIR/dedup_${NORMALIZE_NAME}_master.txt"
    META="$DIR/dedup_${NORMALIZE_NAME}_master.meta"
    if [[ ! -f "$MASTER" ]]; then
        echo "No master to normalize: $MASTER" >&2
        exit 1
    fi
    EXISTING_MODE="$(read_meta_case "$META" 2>/dev/null || true)"
    if [[ -n "$CASE_FLAG" ]]; then
        TARGET_MODE="$CASE_FLAG"
    elif [[ -n "$EXISTING_MODE" ]]; then
        TARGET_MODE="$EXISTING_MODE"
    else
        TARGET_MODE="$DEFAULT_CASE"
    fi
    TMP="$(mktemp "$MASTER.norm.XXXXXX")"
    BEFORE=$(wc -l < "$MASTER")
    awk "$AWK_TRANSFORM"'
        { line = transform($0, MODE); if (!(line in seen)) { seen[line]=1; print line } }
    ' MODE="$TARGET_MODE" "$MASTER" > "$TMP"
    AFTER=$(wc -l < "$TMP")
    mv -- "$TMP" "$MASTER"
    write_meta_case "$META" "$TARGET_MODE"
    echo "Normalized $MASTER"
    echo "  case:    $TARGET_MODE"
    echo "  before:  $BEFORE lines"
    echo "  after:   $AFTER lines"
    echo "  removed: $((BEFORE - AFTER)) duplicates"
    exit 0
fi

if [[ -z "$INPUT" ]]; then
    echo "Error: no input wordlist given" >&2
    usage >&2
    exit 2
fi

if [[ "$INPUT" != "-" && ! -r "$INPUT" ]]; then
    echo "Error: cannot read '$INPUT'" >&2
    exit 1
fi

mkdir -p "$DIR"
MASTER="$DIR/dedup_${REF}_master.txt"
FILTERED="$DIR/dedup_${REF}_filtered.txt"
META="$DIR/dedup_${REF}_master.meta"

EXISTING_MODE="$(read_meta_case "$META" 2>/dev/null || true)"
if [[ -n "$EXISTING_MODE" ]]; then
    if [[ -n "$CASE_FLAG" && "$CASE_FLAG" != "$EXISTING_MODE" ]]; then
        if [[ "$FORCE_CASE" -eq 1 ]]; then
            echo "Warning: overriding namespace '$REF' case: $EXISTING_MODE → $CASE_FLAG" >&2
            MODE="$CASE_FLAG"
        else
            cat >&2 <<EOF
Error: namespace '$REF' is recorded as case=$EXISTING_MODE but --case $CASE_FLAG was requested.
       Pass --force-case to change it, or run:
         dedup --normalize $REF --case $CASE_FLAG
EOF
            exit 3
        fi
    else
        MODE="$EXISTING_MODE"
    fi
else
    MODE="${CASE_FLAG:-$DEFAULT_CASE}"
fi

SRC="$(mktemp)"
trap 'rm -f "$SRC" "$SRC.new" "$MASTER.tmp"' EXIT

if [[ "$INPUT" == "-" ]]; then
    cat > "$SRC"
else
    cp -- "$INPUT" "$SRC"
fi

[[ -f "$MASTER" ]] || : > "$MASTER"

: > "$SRC.new"
read -r DUP_IN_MASTER DUP_IN_INPUT NEW_UNIQUE < <(
    awk "$AWK_TRANSFORM"'
        FILENAME==MASTER_FILE { master[$0]=1; next }
        {
            line = transform($0, MODE)
            if (line in master)    { dup_master++ }
            else if (line in seen) { dup_input++ }
            else                   { seen[line]=1; print line > OUT }
        }
        END { printf "%d %d %d\n", dup_master+0, dup_input+0, length(seen) }
    ' OUT="$SRC.new" MASTER_FILE="$MASTER" MODE="$MODE" "$MASTER" "$SRC"
)

mv -- "$SRC.new" "$FILTERED"

cp -- "$MASTER" "$MASTER.tmp"
cat "$FILTERED" >> "$MASTER.tmp"
mv -- "$MASTER.tmp" "$MASTER"

write_meta_case "$META" "$MODE"

if [[ "$QUIET" -eq 0 ]]; then
    if [[ -t 1 ]]; then G=$'\033[1;32m'; R=$'\033[0m'; else G=""; R=""; fi
    echo "======================================"
    echo "Filtered unique lines saved to: ${G}${FILTERED}${R}"
    echo "======================================"
    echo "Case mode:                 $MODE"
    echo "Already in master:         $DUP_IN_MASTER"
    echo "Duplicates within input:   $DUP_IN_INPUT"
    echo "New unique lines added:    $NEW_UNIQUE"
    echo "Master updated:            $MASTER"
fi
