#!/usr/bin/env bash
# applocal-patch 001: watch.sh grep -oP → sed (BSD grep 互換)
#
# watch.sh:59 の `grep -oP '"login":\s*"\K[^"]+'` は macOS BSD grep で動かない。
# agent-hub-plugin update のたびに消えてしまうため installer で再適用する。
#
# 使い方:
#   このスクリプトは installer の apply_applocal_patches() から自動呼び出しされる。
#   手動実行: bash applocal-patches/001-watch-sh-grep-oP.sh <watch.sh path>
#
# Idempotent: grep -oP が無ければ何もしない。

set -euo pipefail

WATCH_SH="${1:-}"
if [[ -z "${WATCH_SH}" ]]; then
  WATCH_SH=$(find "${HOME}/.claude" -name watch.sh 2>/dev/null | head -1 || true)
fi

if [[ -z "${WATCH_SH}" ]]; then
  echo "[skip] watch.sh not found (agent-hub plugin not installed)"
  exit 0
fi

if ! grep -q 'grep -oP' "${WATCH_SH}" 2>/dev/null; then
  echo "[skip] watch.sh already patched or pattern not present"
  exit 0
fi

echo "[apply] patching ${WATCH_SH} (grep -oP → sed)"

# Write a Python patcher to a temp file (avoids shell quoting issues with grep -oP pattern)
_py=$(mktemp /tmp/agent-hub-patch001-XXXXXX.py 2>/dev/null || echo "/tmp/agent-hub-patch001-$$.py")
cat > "${_py}" << 'PYTHON_EOF'
import sys, os

fname = os.environ.get('PATCH_FILE', '')
if not fname:
    print("[err] PATCH_FILE not set", file=sys.stderr)
    sys.exit(1)

with open(fname) as f:
    content = f.read()

OLD = "grep -oP '\"login\":\\s*\"\\K[^\"]+'"
NEW = "sed -nE 's/.*\"login\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\\1/p' | head -1"

if OLD not in content:
    # Try alternate quoting style
    OLD2 = 'grep -oP \'"login":\\s*"\\K[^"]+\''
    if OLD2 not in content:
        print("[skip] grep -oP pattern not found in expected form")
        sys.exit(0)
    OLD = OLD2

with open(fname, 'w') as f:
    f.write(content.replace(OLD, NEW))
print(f"[ok] patched {fname}")
PYTHON_EOF

PATCH_FILE="${WATCH_SH}" python3 "${_py}"
_exit=$?
rm -f "${_py}"
exit ${_exit}
