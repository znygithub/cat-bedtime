#!/usr/bin/env bash
# Cat Bedtime installer
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/i18n.sh"
source "$SCRIPT_DIR/lib/ui.sh"

clear 2>/dev/null || true
ui_moon

ui_print "  ${BOLD}$(msg install.title)${RESET}"
ui_blank

ui_step "$(msg install.step.check)"

if [[ "$(uname)" != "Darwin" ]]; then
  ui_error "$(msg install.error.macos)"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  ui_error "$(msg install.error.python)"
  exit 1
fi

ui_success "$(msg install.check_ok)"

INSTALL_DIR="$HOME/.timetosleep"
ui_step "$(msg install.step.dir)"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/src"
mkdir -p "$INSTALL_DIR/assets"
mkdir -p "$INSTALL_DIR/locales"

ui_step "$(msg install.step.files)"
if [ ! -f "$SCRIPT_DIR/locales/messages.json" ]; then
  ui_error "缺少 locales/messages.json。请从完整发布包安装，或 git clone 整个仓库。"
  exit 1
fi
cp -r "$SCRIPT_DIR/lib/"* "$INSTALL_DIR/lib/"
cp -r "$SCRIPT_DIR/src/"* "$INSTALL_DIR/src/"
cp "$SCRIPT_DIR/locales/messages.json" "$INSTALL_DIR/locales/messages.json"

if [ -d "$SCRIPT_DIR/assets" ]; then
  cp -r "$SCRIPT_DIR/assets/"* "$INSTALL_DIR/assets/" 2>/dev/null || true
fi

cp "$SCRIPT_DIR/bin/zzz" "$INSTALL_DIR/bin/zzz"
cp "$SCRIPT_DIR/bin/zzz-overlay" "$INSTALL_DIR/bin/zzz-overlay"
chmod +x "$INSTALL_DIR/bin/zzz"
chmod +x "$INSTALL_DIR/bin/zzz-overlay"
chmod +x "$INSTALL_DIR/src/cli/daemon.sh"

ui_step "$(msg install.step.link)"

LINKED=false

if [ -w "/usr/local/bin" ]; then
  ln -sf "$INSTALL_DIR/bin/zzz" "/usr/local/bin/zzz"
  ui_success "$(msg install.linked)"
  LINKED=true
fi

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
  ui_success "$(msg install.path_added)"
fi

ui_blank
ui_box "$(printf '%b\n' \
  "${C_GREEN}${BOLD}$(msg install.done.title)${RESET}" \
  "" \
  "$(msg install.done.next)")"
ui_blank

sleep 1

osascript -e "
tell application \"Terminal\"
    activate
    do script \"'$INSTALL_DIR/bin/zzz' init\"
end tell
"
