#!/usr/bin/env bash
# check_env.sh - Verifies that the tools required for the CA1 DApp are installed.

echo "=== CA1 Blockchain - Environment Check ==="

check() {
  # "--version" must succeed (avoids the Windows Store "python3" alias false positive)
  if command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1; then
    echo "[OK]      $1 -> $($1 --version 2>&1 | head -n 1)"
  else
    echo "[MISSING] $1"
  fi
}

check python
check python3
check node
check npm
check ganache

# Check the Python libraries (web3 + solc compiler)
for PY in python3 python; do
  if command -v "$PY" >/dev/null 2>&1 && $PY -c "import web3, solcx" >/dev/null 2>&1; then
    echo "[OK]      web3 + py-solc-x (Python libraries)"
    FOUND=1
    break
  fi
done
if [ -z "$FOUND" ]; then
  echo "[MISSING] Python libraries -> install with: pip install web3 py-solc-x"
fi

echo "=========================================="
