#!/usr/bin/env bash
set -euo pipefail

# Installs dedup.sh as `dedup` on your PATH.
# Usage:
#   ./install.sh                 # installs to ~/.local/bin (user)
#   ./install.sh --system        # installs to /usr/local/bin (needs sudo)
#   ./install.sh --prefix /opt   # installs to /opt/bin
#   ./install.sh --uninstall     # removes the installed symlink/binary

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SRC_DIR/dedup.sh"
NAME="dedup"

MODE="user"
PREFIX=""
UNINSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system)    MODE="system"; shift ;;
        --prefix)    MODE="prefix"; PREFIX="${2:?--prefix requires a path}"; shift 2 ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help)
            sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

case "$MODE" in
    user)   DEST_DIR="$HOME/.local/bin" ;;
    system) DEST_DIR="/usr/local/bin" ;;
    prefix) DEST_DIR="$PREFIX/bin" ;;
esac

DEST="$DEST_DIR/$NAME"

need_sudo() {
    [[ "$MODE" == "system" && "$(id -u)" -ne 0 ]]
}
run() { if need_sudo; then sudo "$@"; else "$@"; fi; }

if [[ "$UNINSTALL" -eq 1 ]]; then
    if [[ -e "$DEST" || -L "$DEST" ]]; then
        run rm -f "$DEST"
        echo "Removed $DEST"
    else
        echo "Nothing to remove at $DEST"
    fi
    exit 0
fi

[[ -f "$SCRIPT" ]] || { echo "dedup.sh not found at $SCRIPT" >&2; exit 1; }

chmod +x "$SCRIPT"
run mkdir -p "$DEST_DIR"
run ln -sfn "$SCRIPT" "$DEST"

echo "Installed: $DEST -> $SCRIPT"

case ":$PATH:" in
    *":$DEST_DIR:"*) ;;
    *) echo
       echo "WARNING: $DEST_DIR is not on your PATH."
       echo "Add this to your shell rc (e.g. ~/.bashrc or ~/.zshrc):"
       echo "    export PATH=\"$DEST_DIR:\$PATH\""
       ;;
esac
