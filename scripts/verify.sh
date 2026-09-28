#!/data/data/com.termux/files/usr/bin/bash
# verify.sh - Healthcheck and verification script for Muse Code on Termux
# Author: itswill00 <anstykx00@gmail.com>

set -euo pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"

echo "==> Running Muse Code on Termux Verification Suite..."

pass() { echo -e "${GREEN}[PASS]${RESET} $1"; }
fail() { echo -e "${RED}[FAIL]${RESET} $1"; exit 1; }

# 1. Check if muse is in PATH
if command -v muse >/dev/null 2>&1; then
  pass "Command 'muse' found in PATH: $(command -v muse)"
else
  fail "Command 'muse' not found in PATH"
fi

# 2. Check termux-chroot / proot
if command -v termux-chroot >/dev/null 2>&1; then
  pass "termux-chroot (PRoot) is installed"
else
  fail "termux-chroot is not installed. Install with 'pkg install proot'"
fi

# 3. Test version
version_out=$(muse --version 2>&1) || fail "muse --version failed: $version_out"
pass "Version check: $version_out"

# 4. Test headless execution
test_out=$(muse exec --provider echo "test-ok" 2>&1)
if [[ "$test_out" =~ "echo: test-ok" ]]; then
  pass "Headless exec test succeeded"
else
  fail "Headless exec test failed. Output: $test_out"
fi

echo -e "\n${GREEN}[✓] All checks passed! Muse Code is fully operational on Termux.${RESET}"
