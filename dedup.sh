#!/usr/bin/env bash
set -euo pipefail

PROG="$(basename "$0")"
usage() {
    cat <<EOF
Usage: $PROG [-m <reference_name>] [-d <dir>] [-q] <new_wordlist | ->

Maintain a per-reference master wordlist and emit only words not previously seen.

  -m, --master <name>   Reference namespace (default: "default")
  -d, --dir <path>      Directory for master/filtered files
                        (default: \$DEDUP_DIR, else current directory)
  -q, --quiet           Suppress summary output
  -h, --help            Show this help

Reads from stdin if <new_wordlist> is "-".
Files produced:
  <dir>/dedup_<name>_master.txt
  <dir>/dedup_<name>_filtered.txt
EOF
}

REF="default"
DIR="${DEDUP_DIR:-.}"
QUIET=0
INPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--master) REF="${2:?missing value for $1}"; shift 2 ;;
        -d|--dir)    DIR="${2:?missing value for $1}"; shift 2 ;;
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
    awk -v OUT="$SRC.new" -v MASTER_FILE="$MASTER" '
        FILENAME==MASTER_FILE { master[$0]=1; next }
        {
            if ($0 in master)    { dup_master++ }
            else if ($0 in seen) { dup_input++ }
            else                 { seen[$0]=1; print > OUT }
        }
        END { printf "%d %d %d\n", dup_master+0, dup_input+0, length(seen) }
    ' "$MASTER" "$SRC"
)

mv -- "$SRC.new" "$FILTERED"

cp -- "$MASTER" "$MASTER.tmp"
cat "$FILTERED" >> "$MASTER.tmp"
mv -- "$MASTER.tmp" "$MASTER"

if [[ "$QUIET" -eq 0 ]]; then
    if [[ -t 1 ]]; then G=$'\033[1;32m'; R=$'\033[0m'; else G=""; R=""; fi
    echo "======================================"
    echo "Filtered unique lines saved to: ${G}${FILTERED}${R}"
    echo "======================================"
    echo "Already in master:         $DUP_IN_MASTER"
    echo "Duplicates within input:   $DUP_IN_INPUT"
    echo "New unique lines added:    $NEW_UNIQUE"
    echo "Master updated:            $MASTER"
fi
