#!/usr/bin/env bash
# check_env.sh - Verifies that the tools required for the CA1 DApp are installed.

echo "=== CA1 Blockchain - Environment Check ==="

check() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "[OK]      $1 -> $($1 --version 2>&1 | head -n 1)"
  else
    echo "[MISSING] $1"
  fi
}

check python3
check pip3
check node
check npm
check ganache

# Check if the web3 Python library is installed
if python3 -c "import web3" >/dev/null 2>&1; then
  echo "[OK]      web3 (Python library)"
else
  echo "[MISSING] web3 (Python library) -> install with: pip3 install web3"
fi

echo "=========================================="
