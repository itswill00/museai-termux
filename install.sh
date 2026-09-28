#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# museai-termux - Automated Installer & Patcher for Meta's Muse Code on Termux
# Repository: https://github.com/itswill00/museai-termux
# Author: itswill00 <anstykx00@gmail.com>
# ==============================================================================

set -euo pipefail

# ANSI color codes
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

log_info()    { printf "${BLUE}[*]${RESET} %s\n" "$*"; }
log_success() { printf "${GREEN}[✓]${RESET} %s\n" "$*"; }
log_warn()    { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
log_err()     { printf "${RED}[✗]${RESET} %s\n" "$*" >&2; }

print_banner() {
  printf "${CYAN}${BOLD}"
  cat << "EOF"
  __  __                  _    ___   _____                               
 |  \/  |_   _ ___  ___  / \  |_ _| |_   _|__ _ __ _ __ ___  _   ___  __
 | |\/| | | | / __|/ _ \/ _ \  | |    | |/ _ \ '__| '_ ` _ \| | | \ \/ /
 | |  | | |_| \__ \  __/ ___ \ | |    | |  __/ |  | | | | | | |_| |>  < 
 |_|  |_|\__,_|___/\___/_/   \_\___|   |_|\___|_|  |_| |_| |_|\__,_/_/\_\
EOF
  printf "${RESET}\n"
  printf "${BOLD}Meta Muse Code Port & Syscall Patcher for Android / Termux${RESET}\n"
  printf "Maintained by: ${CYAN}@itswill00${RESET}\n"
  printf "------------------------------------------------------------------\n\n"
}

# 1. Environment & Architecture Checks
check_env() {
  log_info "Verifying environment prerequisites..."

  if [[ ! -d "/data/data/com.termux" && -z "${PREFIX:-}" ]]; then
    log_err "This installer is designed specifically for Termux on Android."
    exit 1
  fi

  local arch
  arch="$(uname -m)"
  if [[ "$arch" != "aarch64" && "$arch" != "arm64" ]]; then
    log_err "Unsupported CPU architecture: $arch. Meta Muse AI binary currently requires aarch64 (64-bit ARM)."
    exit 1
  fi

  log_success "Environment valid: Android Termux ($arch)"
}

# 2. Install Required Termux Packages
install_deps() {
  log_info "Checking required packages (proot, python, curl)..."
  local missing=()

  for pkg in proot python curl; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_info "Installing missing dependencies: ${missing[*]}..."
    pkg update -y || apt-get update -y
    pkg install -y "${missing[@]}" || apt-get install -y "${missing[@]}"
  fi

  log_success "All dependencies satisfied."
}

# 3. Install Official Muse if Not Present
ensure_muse_installed() {
  local launcher="$HOME/.local/bin/muse"
  if [[ ! -f "$launcher" ]]; then
    log_info "Official Muse installation not found. Downloading via Meta launcher..."
    mkdir -p "$HOME/.local/bin"
    curl -fsSL "https://api.meta.ai/muse-launcher.sh" | bash || {
      log_err "Failed to download and run official Muse installer from api.meta.ai."
      exit 1
    }
  else
    log_info "Existing Muse installation found at $launcher"
  fi
}

# 4. Patch Syscalls in muse-bin Binary
patch_binary() {
  log_info "Patching openat2 syscall in Muse binary to bypass Android seccomp restriction..."

  python3 -c '
import glob, os, sys

old_sig = bytes.fromhex("a8 36 80 52 01 00 00 d4") # mov w8, #437; svc #0
new_sig = bytes.fromhex("a0 04 80 92 1f 20 03 d5") # mov x0, #-38; nop

home = os.environ.get("HOME", "/data/data/com.termux/files/home")
targets = glob.glob(os.path.join(home, ".local", "bin", "muse-bin*"))

if not targets:
    print("[-] No muse-bin binary found to patch.")
    sys.exit(1)

for bin_path in targets:
    if bin_path.endswith(".bak"):
        continue
    with open(bin_path, "rb") as f:
        data = bytearray(f.read())
    
    count = 0
    idx = 0
    while True:
        pos = data.find(old_sig, idx)
        if pos == -1:
            break
        data[pos:pos+8] = new_sig
        count += 1
        idx = pos + 8
    
    if count > 0:
        with open(bin_path, "wb") as f:
            f.write(data)
        os.chmod(bin_path, 0o755)
        print(f"[+] Patched {count} openat2 occurrence(s) in {os.path.basename(bin_path)}")
    elif new_sig in data:
        print(f"[=] Already patched: {os.path.basename(bin_path)}")
    else:
        print(f"[?] No matching syscall pattern found in {os.path.basename(bin_path)}")
'
  log_success "Binary patch step complete."
}

# 5. Patch ~/.local/bin/muse Launcher Script
patch_launcher() {
  local launcher="$HOME/.local/bin/muse"
  log_info "Configuring launcher script ($launcher)..."

  # Fix shebang for Termux
  if command -v termux-fix-shebang >/dev/null 2>&1; then
    termux-fix-shebang "$launcher"
  fi

  python3 -c '
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    content = f.read()

# 1. Inject termux-chroot auto-delegation if not present
chroot_hook = """
# --- Termux chroot delegation injected by museai-termux ---
if [[ ! -d /usr/bin ]] && command -v termux-chroot >/dev/null 2>&1; then
  target_dir="${PWD/#\/data\/data\/com.termux\/files\/home/\/home}"
  args=""
  for arg in "$@"; do
    args="$args $(printf %q "$arg")"
  done
  exec termux-chroot "cd $(printf %q "$target_dir") && exec muse$args"
fi
# --- end chroot delegation ---
"""

if "Termux chroot delegation injected by museai-termux" not in content:
    if "set -euo pipefail" in content:
        content = content.replace("set -euo pipefail", "set -euo pipefail\n" + chroot_hook, 1)
    else:
        content = chroot_hook + "\n" + content

# 2. Inject auto-patcher before exec "$binary"
auto_patcher = """
  # Auto-patch binary before exec in case an update replaced it:
  python3 -c '\''
import sys
p = sys.argv[1]
try:
    with open(p, "rb") as f:
        d = bytearray(f.read())
    old = bytes.fromhex("a8 36 80 52 01 00 00 d4")
    new = bytes.fromhex("a0 04 80 92 1f 20 03 d5")
    if old in d:
        idx = 0
        while True:
            pos = d.find(old, idx)
            if pos == -1: break
            d[pos:pos+8] = new
            idx = pos + 8
        with open(p, "wb") as f:
            f.write(d)
except Exception:
    pass
'\'' "$binary" 2>/dev/null || true
"""

if "Auto-patch binary before exec" not in content:
    if "exec \"$binary\" \"$@\"" in content:
        content = content.replace("exec \"$binary\" \"$@\"", auto_patcher + "  exec \"$binary\" \"$@\"", 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
' "$launcher"

  chmod +x "$launcher"
  log_success "Launcher script patched."
}

# 6. Configure Workspace Trust & Environment
setup_config() {
  log_info "Configuring workspace trust and PATH..."

  local config_dir="$HOME/.config/muse"
  mkdir -p "$config_dir"

  cat << 'EOF' > "$config_dir/trust.json"
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

  local bashrc="$HOME/.bashrc"
  local zshrc="$HOME/.zshrc"

  for rc in "$bashrc" "$zshrc"; do
    if [[ -f "$rc" ]]; then
      if ! grep -q '\.local/bin' "$rc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
      fi
    fi
  done

  export PATH="$HOME/.local/bin:$PATH"
  log_success "Configuration and workspace trust configured."
}

# 7. Verification Test
verify_installation() {
  log_info "Testing Muse installation..."
  if muse --version >/dev/null 2>&1; then
    local version
    version="$(muse --version)"
    log_success "Verification passed: $version"
  else
    log_warn "Verification did not return clean exit code, checking help..."
    muse --help | head -n 5 || true
  fi
}

main() {
  print_banner
  check_env
  install_deps
  ensure_muse_installed
  patch_binary
  patch_launcher
  setup_config
  verify_installation

  printf "\n${GREEN}${BOLD}==================================================================${RESET}\n"
  printf "${GREEN}${BOLD}✓ Meta Muse Code has been successfully installed and patched!${RESET}\n"
  printf "${BOLD}  To start Muse, simply run:${RESET}\n"
  printf "  ${CYAN}${BOLD}$ muse${RESET}\n\n"
  printf "  ${BOLD}To test headless mode:${RESET}\n"
  printf "  ${CYAN}$ muse exec --provider echo \"Hello from Termux!\"${RESET}\n"
  printf "${GREEN}${BOLD}==================================================================${RESET}\n"
}

main "$@"
