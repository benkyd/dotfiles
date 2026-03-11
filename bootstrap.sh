#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$HOME"
BACKUP_DIR="$HOME/dotfiles.bak"

echo "Ben's dotfiles"
echo "=============="
echo "Dotfiles dir: $DOTFILES_DIR"
echo "Home dir:     $HOME_DIR"
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

# --- tmux plugin manager ---
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "==> Installing tmux plugin manager..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    echo "  Done. Run <C-b>I in tmux to install plugins."
    echo ""
fi

# --- fish plugin manager ---
if command -v fish &>/dev/null; then
    if ! fish -c "type -q fisher" 2>/dev/null; then
        echo "==> Installing fisher (fish plugin manager)..."
        fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
        echo ""
    fi
fi

# --- $HOME symlinks ---
echo "==> Symlinking home files..."

find "$DOTFILES_DIR" -maxdepth 1 -name '.*' -not -name '.git' -not -name '.gitignore' -not -name '.gitmodules' | while read -r src; do
    item="$(basename "$src")"
    dst="$HOME_DIR/$item"

    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        echo "  ok  $item"
        continue
    fi

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        backup="$BACKUP_DIR/$item"
        mkdir -p "$(dirname "$backup")"
        mv "$dst" "$backup"
        echo "  bak $item -> dotfiles.bak/$item"
    fi

    ln -s "$src" "$dst"
    echo "  ln  $item"
done

if [ -d "$DOTFILES_DIR/pictures" ]; then
    dst="$HOME_DIR/pictures"
    src="$DOTFILES_DIR/pictures"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        echo "  ok  pictures"
    else
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            mv "$dst" "$BACKUP_DIR/pictures"
            echo "  bak pictures -> dotfiles.bak/pictures"
        fi
        ln -s "$src" "$dst"
        echo "  ln  pictures"
    fi
fi

echo ""

# --- /etc copies ---
if [ -d "$DOTFILES_DIR/etc" ]; then
    etc_files=$(find "$DOTFILES_DIR/etc" -type f 2>/dev/null)
    if [ -n "$etc_files" ]; then
        echo "==> System config files found in etc/"

        echo "$etc_files" | while read -r src; do
            rel="${src#$DOTFILES_DIR/}"
            echo "  /$rel"
        done

        echo ""
        read -p "Copy system configs to /etc? This requires sudo. [y/N] " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$etc_files" | while read -r src; do
                rel="${src#$DOTFILES_DIR/}"
                dst="/$rel"

                if [ -f "$dst" ]; then
                    backup="$BACKUP_DIR/$rel"
                    sudo mkdir -p "$(dirname "$backup")"
                    sudo cp "$dst" "$backup"
                    echo "  bak /$rel -> dotfiles.bak/$rel"
                fi

                sudo mkdir -p "$(dirname "$dst")"
                sudo cp "$src" "$dst"
                echo "  cp  $rel"
            done
        else
            echo "  Skipped."
        fi
    fi
fi

echo ""
echo "Done. Backup at ~/dotfiles.bak/ (if anything was moved)"
