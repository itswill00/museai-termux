#!/usr/bin/env python3
"""
patch-binary.py - Syscall patcher for Muse Code AI binary on Android / Termux.
Author: itswill00 <anstykx00@gmail.com>

On Android kernels / seccomp policy, the openat2(2) syscall (syscall 437) is
blocked and immediately triggers SIGSYS (Bad system call). This patcher neutralizes
direct openat2 assembly invocations (mov w8, #437; svc #0) and substitutes them with
a direct assignment of -ENOSYS (x0 = -38; nop), allowing Muse's internal fallback
to standard openat(2) to function normally.
"""

import glob
import os
import sys

# AArch64 machine instructions:
# Original: mov w8, #0x1b5 (437); svc #0
OLD_PATTERN = bytes.fromhex("a8 36 80 52 01 00 00 d4")

# Replacement: mov x0, #-38 (-ENOSYS); nop
NEW_PATTERN = bytes.fromhex("a0 04 80 92 1f 20 03 d5")


def patch_file(target_path: str) -> bool:
    if not os.path.isfile(target_path):
        print(f"[-] File not found: {target_path}", file=sys.stderr)
        return False

    print(f"[*] Inspecting: {target_path}")
    try:
        with open(target_path, "rb") as f:
            data = bytearray(f.read())
    except Exception as e:
        print(f"[-] Failed to read {target_path}: {e}", file=sys.stderr)
        return False

    count = 0
    idx = 0
    while True:
        pos = data.find(OLD_PATTERN, idx)
        if pos == -1:
            break
        data[pos : pos + len(NEW_PATTERN)] = NEW_PATTERN
        count += 1
        idx = pos + len(NEW_PATTERN)

    if count > 0:
        try:
            with open(target_path, "wb") as f:
                f.write(data)
            # Ensure file remains executable
            st = os.stat(target_path)
            os.chmod(target_path, st.st_mode | 0o111)
            print(f"[+] Successfully patched {count} openat2 occurrence(s) in {os.path.basename(target_path)}")
            return True
        except Exception as e:
            print(f"[-] Failed to write patched binary {target_path}: {e}", file=sys.stderr)
            return False
    else:
        # Check if already patched
        if NEW_PATTERN in data:
            print(f"[=] Binary is already patched: {os.path.basename(target_path)}")
            return True
        else:
            print(f"[?] Pattern not found in {os.path.basename(target_path)} (binary may use different compilation or version)")
            return False


def main():
    if len(sys.argv) > 1:
        targets = sys.argv[1:]
    else:
        # Auto-detect default muse binary installation location
        home = os.environ.get("HOME", "")
        pattern = os.path.join(home, ".local", "bin", "muse-bin*")
        targets = glob.glob(pattern)
        if not targets:
            print("[-] No muse-bin binary found in ~/.local/bin/.", file=sys.stderr)
            print("    Usage: python3 patch-binary.py [/path/to/muse-bin]", file=sys.stderr)
            sys.exit(1)

    success_all = True
    for target in targets:
        if not patch_file(target):
            success_all = False

    sys.exit(0 if success_all else 1)


if __name__ == "__main__":
    main()
