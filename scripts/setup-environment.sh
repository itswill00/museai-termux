#!/data/data/com.termux/files/usr/bin/bash
# setup-environment.sh - Configures environment & workspace trust for Muse Code on Termux.
# Author: itswill00 <anstykx00@gmail.com>

set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
MUSE_CONFIG_DIR="$HOME_DIR/.config/muse"
TRUST_FILE="$MUSE_CONFIG_DIR/trust.json"

echo "==> Configuring Muse Code environment..."

# 1. Ensure config directory exists
mkdir -p "$MUSE_CONFIG_DIR"

# 2. Configure trust.json with both /home and full Termux HOME path
cat << 'EOF' > "$TRUST_FILE"
{
  "schema_version": 1,
  "projects": {
    "/home": {
      "decision": "trusted"
    },
    "/data/data/com.termux/files/home": {
      "decision": "trusted"
    }
  }
}
EOF
echo "[+] Workspace trust updated in $TRUST_FILE"

# 3. Ensure ~/.local/bin is in PATH for bash and zsh
add_path() {
  local rc_file="$1"
  if [[ -f "$rc_file" ]]; then
    if ! grep -q '\.local/bin' "$rc_file"; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
      echo "[+] Added ~/.local/bin to PATH in $rc_file"
    fi
  fi
}

add_path "$HOME_DIR/.bashrc"
add_path "$HOME_DIR/.zshrc"
add_path "$HOME_DIR/.profile"

echo "[✓] Environment setup completed successfully."
