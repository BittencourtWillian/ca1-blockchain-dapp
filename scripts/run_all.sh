#!/usr/bin/env bash
# run_all.sh - runs the full FarmToKitchen DApp demo with one command.
# 1) checks the environment  2) checks Ganache is running  3) runs the Python demo
#
# Usage (Git Bash / Linux / macOS), from the project folder:
#   Terminal 1:  ganache --wallet.deterministic
#   Terminal 2:  bash scripts/run_all.sh

cd "$(dirname "$0")/.." || exit 1

echo ">>> Step 1/3 - Environment check"
bash scripts/check_env.sh

echo ">>> Step 2/3 - Checking Ganache on http://127.0.0.1:8545"
if curl -s -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
     http://127.0.0.1:8545 > /dev/null; then
  echo "[OK] Ganache is running"
else
  echo "[ERROR] Ganache is not running. Open another terminal and run: ganache --wallet.deterministic"
  exit 1
fi

# Use "python" on Windows, "python3" on Linux/macOS
if python3 -c "import web3" > /dev/null 2>&1; then
  PY=python3
else
  PY=python
fi

echo ">>> Step 3/3 - Deploying the contract and running the scenarios"
$PY scripts/farm_to_kitchen.py
