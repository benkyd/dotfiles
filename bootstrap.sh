#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/dotfiles.bak"
USER="$(whoami)"

usage() {
    echo "Usage: ./bootstrap.sh [--pull]"
    echo ""
    echo "  (no args)   Install packages, sync repo -> system"
    echo "  --pull      Sync system -> repo (pull changes back)"
    exit 0
}

# --- Pull mode: copy live files back into the repo ---
pull_back() {
    OVERLAY_HOME="$DOTFILES_DIR/home/$USER"
    if [ ! -d "$OVERLAY_HOME" ]; then
        OVERLAY_HOME="$DOTFILES_DIR/home/benk"
    fi

    echo "==> Pulling home files back into repo..."
    rsync -av --itemize-changes --existing --update \
        "$HOME/" "$OVERLAY_HOME/"
    echo ""

    if [ -d "$DOTFILES_DIR/etc" ]; then
        echo "==> Pulling /etc files back into repo..."
        sudo rsync -av --itemize-changes --existing --update \
            /etc/ "$DOTFILES_DIR/etc/"
        echo ""
    fi

    echo "Done. Review changes with 'git diff' then commit."
    exit 0
}

if [[ "${1:-}" == "--pull" ]]; then
    pull_back
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

echo "Ben's dotfiles"
echo "=============="
echo "Repo:     $DOTFILES_DIR"
echo "User:     $USER"
echo ""

# --- Detect OS ---
OS="unknown"
if [[ "$(uname)" == "Darwin" ]]; then
    OS="macos"
elif [[ -f /etc/arch-release ]]; then
    OS="arch"
elif [[ -f /etc/os-release ]]; then
    OS="linux"
fi
echo "Detected OS: $OS"
echo ""

# --- Package installation ---
install_packages() {
    case "$OS" in
        macos)
            if ! command -v brew &>/dev/null; then
                echo "==> Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
            echo "==> Installing packages via brew..."
            xargs brew install < "$DOTFILES_DIR/packages/brew.txt"
            ;;
        arch)
            if ! command -v yay &>/dev/null; then
                echo "==> Installing yay..."
                sudo pacman -S --needed --noconfirm git base-devel
                tmpdir=$(mktemp -d)
                git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
                cd "$tmpdir/yay" && makepkg -si --noconfirm
                cd "$DOTFILES_DIR"
                rm -rf "$tmpdir"
            fi
            echo "==> Installing packages via yay..."
            xargs yay -S --needed --noconfirm < "$DOTFILES_DIR/packages/arch.txt"
            ;;
        *)
            echo "  Unknown OS, skipping package install."
            echo "  Install packages manually from packages/*.txt"
            ;;
    esac
}

read -p "Install packages? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    install_packages
fi
echo ""

# --- Shell tooling ---
echo "==> Setting up shell tooling..."

# tmux plugin manager
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "  Installing tmux plugin manager..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    echo "  Done. Run <C-b>I in tmux to install plugins."
else
    echo "  ok  tmux plugin manager"
fi

# oh-my-fish
if command -v fish &>/dev/null; then
    if [ ! -d "$HOME/.local/share/omf" ]; then
        echo "  Installing oh-my-fish..."
        curl -L https://get.oh-my.fish | fish
    else
        echo "  ok  oh-my-fish"
    fi

    # fisher
    if ! fish -c "type -q fisher" 2>/dev/null; then
        echo "  Installing fisher (fish plugin manager)..."
        fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
    else
        echo "  ok  fisher"
    fi
fi

echo ""

# --- Overlay: home/benk/ -> $HOME ---
OVERLAY_HOME="$DOTFILES_DIR/home/$USER"

if [ ! -d "$OVERLAY_HOME" ]; then
    echo "WARNING: No home overlay for user '$USER', falling back to home/benk/"
    OVERLAY_HOME="$DOTFILES_DIR/home/benk"
fi

echo "==> Syncing $OVERLAY_HOME -> $HOME"
mkdir -p "$BACKUP_DIR/home"
rsync -av --itemize-changes --backup --backup-dir="$BACKUP_DIR/home" \
    "$OVERLAY_HOME/" "$HOME/"
echo ""

# --- Overlay: etc/ -> /etc ---
if [ -d "$DOTFILES_DIR/etc" ]; then
    etc_files=$(find "$DOTFILES_DIR/etc" -type f 2>/dev/null)
    if [ -n "$etc_files" ]; then
        echo "==> System config files in etc/:"
        echo "$etc_files" | while read -r src; do
            echo "  /${src#$DOTFILES_DIR/}"
        done

        echo ""
        read -p "Sync to /etc? Requires sudo. [y/N] " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mkdir -p "$BACKUP_DIR/etc"
            sudo rsync -av --itemize-changes --backup --backup-dir="$BACKUP_DIR/etc" \
                "$DOTFILES_DIR/etc/" /etc/
            echo "  Originals backed up to ~/dotfiles.bak/etc/"
        else
            echo "  Skipped."
        fi
    fi
fi

echo ""
echo "Done. Backups at ~/dotfiles.bak/"
