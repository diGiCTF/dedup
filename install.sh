#!/usr/bin/env bash
set -euo pipefail

# Installs dedup.sh as `dedup` on your PATH, prompts for a storage directory,
# and optionally adds a `dcd` shell helper.
#
# Usage:
#   ./install.sh                     installs to ~/.local/bin
#   ./install.sh --system            installs to /usr/local/bin (sudo)
#   ./install.sh --prefix /opt       installs to /opt/bin
#   ./install.sh --dir <path>        skip the directory prompt
#   ./install.sh --no-config         do not write/update the config file
#   ./install.sh --no-dcd            do not offer the dcd shell helper
#   ./install.sh -y | --yes          accept all defaults non-interactively
#   ./install.sh --uninstall         removes the installed symlink

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SRC_DIR/dedup.sh"
NAME="dedup"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dedup"
CONFIG_FILE="$CONFIG_DIR/config"

MODE="user"
PREFIX=""
UNINSTALL=0
DIR_ARG=""
SKIP_CONFIG=0
SKIP_DCD=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system)     MODE="system"; shift ;;
        --prefix)     MODE="prefix"; PREFIX="${2:?--prefix requires a path}"; shift 2 ;;
        --dir)        DIR_ARG="${2:?--dir requires a path}"; shift 2 ;;
        --no-config)  SKIP_CONFIG=1; shift ;;
        --no-dcd)     SKIP_DCD=1; shift ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --uninstall)  UNINSTALL=1; shift ;;
        -h|--help)    sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

case "$MODE" in
    user)   DEST_DIR="$HOME/.local/bin" ;;
    system) DEST_DIR="/usr/local/bin" ;;
    prefix) DEST_DIR="$PREFIX/bin" ;;
esac
DEST="$DEST_DIR/$NAME"

need_sudo() { [[ "$MODE" == "system" && "$(id -u)" -ne 0 ]]; }
run() { if need_sudo; then sudo "$@"; else "$@"; fi; }

prompt() {
    local msg="$1" default="$2" reply
    if [[ "$ASSUME_YES" -eq 1 || ! -t 0 ]]; then
        printf '%s\n' "$default"
        return
    fi
    read -r -p "$msg [$default]: " reply || reply=""
    printf '%s\n' "${reply:-$default}"
}

confirm() {
    local msg="$1" default="${2:-N}" reply
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        [[ "$default" =~ ^[Yy]$ ]]
        return
    fi
    if [[ ! -t 0 ]]; then
        [[ "$default" =~ ^[Yy]$ ]]
        return
    fi
    local hint="[y/N]"; [[ "$default" =~ ^[Yy]$ ]] && hint="[Y/n]"
    read -r -p "$msg $hint: " reply || reply=""
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy]$ ]]
}

if [[ "$UNINSTALL" -eq 1 ]]; then
    if [[ -e "$DEST" || -L "$DEST" ]]; then
        run rm -f "$DEST"
        echo "Removed $DEST"
    else
        echo "Nothing to remove at $DEST"
    fi
    if [[ -f "$CONFIG_FILE" ]]; then
        if confirm "Also remove config at $CONFIG_FILE?" "N"; then
            rm -f "$CONFIG_FILE"
            rmdir "$CONFIG_DIR" 2>/dev/null || true
            echo "Removed $CONFIG_FILE"
        fi
    fi
    exit 0
fi

[[ -f "$SCRIPT" ]] || { echo "dedup.sh not found at $SCRIPT" >&2; exit 1; }

chmod +x "$SCRIPT"
run mkdir -p "$DEST_DIR"
run ln -sfn "$SCRIPT" "$DEST"
echo "Installed: $DEST -> $SCRIPT"

if [[ "$SKIP_CONFIG" -eq 0 ]]; then
    CURRENT=""
    if [[ -f "$CONFIG_FILE" ]]; then
        CURRENT="$(awk -F= '/^[[:space:]]*DEDUP_DIR[[:space:]]*=/ {sub(/^[[:space:]]*DEDUP_DIR[[:space:]]*=[[:space:]]*/,""); gsub(/^["\x27]|["\x27]$/,""); print; exit}' "$CONFIG_FILE" || true)"
    fi
    DEFAULT_DIR="${DIR_ARG:-${CURRENT:-$HOME/.dedup}}"
    if [[ -n "$DIR_ARG" ]]; then
        CHOSEN="$DIR_ARG"
    else
        echo
        echo "Dedup stores all master/filtered wordlists under one directory."
        echo "This keeps ongoing lists tracked across CTFs, even as you 'cd' around."
        CHOSEN="$(prompt "Where should dedup store wordlists?" "$DEFAULT_DIR")"
    fi
    CHOSEN="${CHOSEN/#\~/$HOME}"
    mkdir -p "$CONFIG_DIR" "$CHOSEN"
    tmp="$(mktemp "$CONFIG_DIR/config.XXXXXX")"
    {
        echo "# dedup config — managed by 'dedup --set-path'. Edit freely."
        echo "DEDUP_DIR=$CHOSEN"
    } > "$tmp"
    mv -- "$tmp" "$CONFIG_FILE"
    echo "Config:    $CONFIG_FILE (DEDUP_DIR=$CHOSEN)"
fi

if [[ "$SKIP_DCD" -eq 0 ]]; then
    RC=""
    case "${SHELL##*/}" in
        zsh)  RC="$HOME/.zshrc" ;;
        bash) RC="$HOME/.bashrc" ;;
        *)    RC="$HOME/.bashrc" ;;
    esac
    MARKER="# >>> dedup dcd helper >>>"
    if grep -qsF "$MARKER" "$RC" 2>/dev/null; then
        echo "dcd helper already present in $RC"
    elif confirm "Add 'dcd' shell helper to $RC (so you can 'cd' into your dedup dir)?" "Y"; then
        {
            echo ""
            echo "$MARKER"
            echo "dcd() { cd \"\$(dedup -p 2>/dev/null)\" || return; }"
            echo "# <<< dedup dcd helper <<<"
        } >> "$RC"
        echo "Added dcd to $RC — run 'source $RC' or open a new shell to use it."
    fi
fi

case ":$PATH:" in
    *":$DEST_DIR:"*) ;;
    *) echo
       echo "WARNING: $DEST_DIR is not on your PATH."
       echo "Add this to your shell rc (e.g. ~/.bashrc or ~/.zshrc):"
       echo "    export PATH=\"$DEST_DIR:\$PATH\""
       ;;
esac
