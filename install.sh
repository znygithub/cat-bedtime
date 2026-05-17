#!/usr/bin/env bash
# Cat Bedtime installer
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/ui.sh"

clear 2>/dev/null || true
ui_moon

ui_print "  ${BOLD}安装 Cat Bedtime${RESET}"
ui_blank

# ── 1. Check prerequisites ──
ui_step "检查环境..."

if [[ "$(uname)" != "Darwin" ]]; then
  ui_error "Cat Bedtime 目前只支持 macOS"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  ui_error "需要 Python 3（macOS 通常自带）"
  exit 1
fi

ui_success "环境检查通过"

# ── 2. Create install directory ──
INSTALL_DIR="$HOME/.timetosleep"
ui_step "创建安装目录..."
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/src"
mkdir -p "$INSTALL_DIR/assets"

# ── 3. Copy files ──
ui_step "安装文件..."
cp -r "$SCRIPT_DIR/lib/"* "$INSTALL_DIR/lib/"
cp -r "$SCRIPT_DIR/src/"* "$INSTALL_DIR/src/"

# Copy assets (cat image, animation video)
if [ -d "$SCRIPT_DIR/assets" ]; then
  cp -r "$SCRIPT_DIR/assets/"* "$INSTALL_DIR/assets/" 2>/dev/null || true
fi

# Copy binaries
cp "$SCRIPT_DIR/bin/zzz" "$INSTALL_DIR/bin/zzz"
cp "$SCRIPT_DIR/bin/zzz-overlay" "$INSTALL_DIR/bin/zzz-overlay"
if [ -d "$SCRIPT_DIR/bin/Cat Bedtime.app" ]; then
  rm -rf "$INSTALL_DIR/bin/Cat Bedtime.app"
  cp -R "$SCRIPT_DIR/bin/Cat Bedtime.app" "$INSTALL_DIR/bin/Cat Bedtime.app"
fi
chmod +x "$INSTALL_DIR/bin/zzz"
chmod +x "$INSTALL_DIR/bin/zzz-overlay"
chmod +x "$INSTALL_DIR/src/cli/daemon.sh"

# ── 4. Create symlink ──
ui_step "创建 zzz 命令..."

LINKED=false

# Try /usr/local/bin first
if [ -w "/usr/local/bin" ]; then
  ln -sf "$INSTALL_DIR/bin/zzz" "/usr/local/bin/zzz"
  ui_success "已安装到 /usr/local/bin/zzz"
  LINKED=true
fi

# Fallback: add to PATH via shell profile
if [ "$LINKED" = false ]; then
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$rc" ]; then
      if ! grep -q '.timetosleep/bin' "$rc" 2>/dev/null; then
        echo '' >> "$rc"
        echo '# Cat Bedtime' >> "$rc"
        echo 'export PATH="$HOME/.timetosleep/bin:$PATH"' >> "$rc"
      fi
      LINKED=true
      break
    fi
  done
  if [ "$LINKED" = false ]; then
    echo '# Cat Bedtime' >> "$HOME/.zshrc"
    echo 'export PATH="$HOME/.timetosleep/bin:$PATH"' >> "$HOME/.zshrc"
    LINKED=true
  fi
  export PATH="$HOME/.timetosleep/bin:$PATH"
  ui_success "已添加到 PATH（重启终端或 source ~/.zshrc 生效）"
fi

# ── 5. Done ──
ui_blank
ui_box "$(printf '%b\n' \
  "${C_GREEN}${BOLD}安装完成！${RESET}" \
  "" \
  "即将进入猫猫领养设置...")"
ui_blank

sleep 1

# ── 6. Launch onboarding in a visible Terminal window ──
osascript -e "
tell application \"Terminal\"
    activate
    do script \"'$INSTALL_DIR/bin/zzz' init\"
end tell
"
