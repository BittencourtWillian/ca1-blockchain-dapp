"""
farm_to_kitchen.py

Deploys the FarmToKitchen smart contract to a local Ganache blockchain and runs
three end-to-end scenarios with (test) ETH payments:

  A) Delivery accepted      -> payment released to the supplier
  B) Cold chain broken      -> automatic refund to the kitchen
  C) Batch recalled         -> refund to the kitchen
  + Validation test         -> order to an unregistered supplier is rejected

Accounts used (Ganache):
  accounts[0] = Regulator (deploys the contract)
  accounts[1] = Supplier  (sender)
  accounts[2] = Kitchen   (receiver)

Requirements:  pip install web3 py-solc-x
Run:           python scripts/farm_to_kitchen.py   (with Ganache running on port 8545)
"""

import json
import sys
import time
from pathlib import Path

from web3 import Web3
from solcx import compile_standard, install_solc

GANACHE_URL = "http://127.0.0.1:8545"
SOLC_VERSION = "0.8.20"
ROOT = Path(__file__).resolve().parent.parent
CONTRACT_FILE = ROOT / "contracts" / "FarmToKitchen.sol"
DEPLOYMENT_FILE = ROOT / "scripts" / "deployment.json"
STATUS = ["Ordered", "Dispatched", "Delivered", "Accepted", "Rejected", "Recalled"]


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
def title(text):
    print("\n" + "=" * 64)
    print(text)
    print("=" * 64)


def eth(wei):
    sign = "-" if wei < 0 else ""
    return f"{sign}{float(Web3.from_wei(abs(wei), 'ether')):.4f} ETH"


def revert_reason(err):
    """Extracts the short reason message from a reverted transaction."""
    msg = str(err.args[0]) if err.args else str(err)
    return msg.split("revert ")[-1] if "revert " in msg else msg


def compile_contract():
    print(f"Compiling {CONTRACT_FILE.name} with solc {SOLC_VERSION} ...")
    install_solc(SOLC_VERSION)
    source = CONTRACT_FILE.read_text(encoding="utf-8")
    compiled = compile_standard(
        {
            "language": "Solidity",
            "sources": {"FarmToKitchen.sol": {"content": source}},
            "settings": {
                "evmVersion": "paris",  # compatible with Ganache
                "outputSelection": {"*": {"*": ["abi", "evm.bytecode.object"]}},
            },
        },
        solc_version=SOLC_VERSION,
    )
    data = compiled["contracts"]["FarmToKitchen.sol"]["FarmToKitchen"]
    return data["abi"], data["evm"]["bytecode"]["object"]


def send(w3, fn, sender, value=0):
    """Sends a transaction and waits for it to be mined."""
    tx_hash = fn.transact({"from": sender, "value": value})
    return w3.eth.wait_for_transaction_receipt(tx_hash)


def show_batch(contract, batch_id):
    b = contract.functions.getBatch(batch_id).call()
    print(f"  Batch #{b[0]} | {b[3]} | {b[4]} kg | max {b[5]} C")
    print(f"    Origin: {b[7] or '-'} | Lot: {b[8] or '-'}")
    print(f"    Temperature readings: {b[11]} | highest: {b[12]} C | cold chain broken: {b[13]}")
    print(f"    Payment in escrow: {eth(b[6])} | STATUS: {STATUS[b[14]]}")


def run_delivery(w3, c, supplier, kitchen, product, temps, accept, label):
    """Full flow: order -> dispatch -> temperatures -> delivered -> confirm."""
    title(label)
    sup_before = w3.eth.get_balance(supplier)
    kit_before = w3.eth.get_balance(kitchen)

    # 1. Kitchen places the order and pays 1 ETH (escrow)
    send(w3, c.functions.placeOrder(supplier, product, 20, 5), kitchen, Web3.to_wei(1, "ether"))
    batch_id = c.functions.batchCount().call()
    print(f"1) Kitchen ordered '{product}' and paid 1 ETH -> escrow: {eth(c.functions.getEscrowBalance().call())}")

    # 2. Supplier dispatches with traceability data + certificate hash
    cert_text = f"Organic certificate - Lot A{100 + batch_id}"
    cert_hash = c.functions.hashDocument(cert_text).call()
    expiry = int(time.time()) + 30 * 24 * 3600
    send(w3, c.functions.dispatchBatch(batch_id, "Green Farm, Co. Meath", f"A{100 + batch_id}", expiry, cert_hash), supplier)
    print(f"2) Supplier dispatched the batch. Certificate hash: 0x{cert_hash.hex().removeprefix('0x')[:16]}...")

    # 3. Temperature readings during transport
    for t in temps:
        send(w3, c.functions.recordTemperature(batch_id, t), supplier)
        print(f"3) Temperature recorded: {t} C {'(OK)' if t <= 5 else '(ABOVE LIMIT!)'}")

    # 4. Supplier marks as delivered
    send(w3, c.functions.markDelivered(batch_id), supplier)
    print("4) Supplier marked the batch as delivered")

    # 5. Kitchen confirms
    send(w3, c.functions.confirmDelivery(batch_id, accept), kitchen)
    print(f"5) Kitchen {'ACCEPTED' if accept else 'REJECTED'} the delivery")

    show_batch(c, batch_id)
    print(f"  Supplier balance change: {eth(w3.eth.get_balance(supplier) - sup_before)} (minus gas)")
    print(f"  Kitchen balance change:  {eth(w3.eth.get_balance(kitchen) - kit_before)} (incl. gas)")
    return batch_id


# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
def main():
    w3 = Web3(Web3.HTTPProvider(GANACHE_URL))
    if not w3.is_connected():
        print(f"ERROR: cannot connect to Ganache at {GANACHE_URL}. Start it with: ganache --wallet.deterministic")
        sys.exit(1)

    regulator, supplier, kitchen = w3.eth.accounts[0], w3.eth.accounts[1], w3.eth.accounts[2]
    title("FarmToKitchen DApp - Ganache demo")
    print(f"Regulator: {regulator}\nSupplier:  {supplier}\nKitchen:   {kitchen}")

    # Deploy
    abi, bytecode = compile_contract()
    Contract = w3.eth.contract(abi=abi, bytecode=bytecode)
    receipt = send(w3, Contract.constructor(), regulator)
    c = w3.eth.contract(address=receipt.contractAddress, abi=abi)
    print(f"Contract deployed at: {receipt.contractAddress}")
    DEPLOYMENT_FILE.write_text(json.dumps({"address": receipt.contractAddress, "abi": abi}, indent=2))

    # Register supplier
    send(w3, c.functions.registerSupplier(supplier), regulator)
    print(f"Supplier registered by regulator: {c.functions.isSupplier(supplier).call()}")

    # Validation test: order to an unregistered address must fail
    title("VALIDATION TEST - order to an unregistered supplier")
    try:
        send(w3, c.functions.placeOrder(kitchen, "Fish", 5, 2), kitchen, Web3.to_wei(1, "ether"))
        print("  UNEXPECTED: order was accepted")
    except Exception as err:
        print(f"  Rejected as expected -> \"{revert_reason(err)}\"")

    # Scenario A - everything OK
    run_delivery(w3, c, supplier, kitchen, "Chicken breast", [3, 4],
                 accept=True, label="SCENARIO A - Cold chain OK, kitchen accepts")

    # Scenario B - cold chain broken: kitchen tries to accept, contract refunds anyway
    run_delivery(w3, c, supplier, kitchen, "Salmon fillet", [4, 9],
                 accept=True, label="SCENARIO B - Cold chain broken (9 C > 5 C)")

    # Scenario C - recall by regulator before delivery
    title("SCENARIO C - Regulator recalls a batch")
    send(w3, c.functions.placeOrder(supplier, "Spinach", 10, 5), kitchen, Web3.to_wei(1, "ether"))
    batch_id = c.functions.batchCount().call()
    print(f"Kitchen ordered 'Spinach' (batch #{batch_id}) -> escrow: {eth(c.functions.getEscrowBalance().call())}")
    send(w3, c.functions.recallBatch(batch_id, "Listeria found at the farm"), regulator)
    print("Regulator recalled the batch: 'Listeria found at the farm'")
    show_batch(c, batch_id)

    # Certificate verification (tamper detection)
    title("CERTIFICATE VERIFICATION (Keccak-256)")
    print(f"  Original document 'Organic certificate - Lot A101': "
          f"{c.functions.verifyCertificate(1, 'Organic certificate - Lot A101').call()}")
    print(f"  Tampered document 'Organic certificate - Lot A999': "
          f"{c.functions.verifyCertificate(1, 'Organic certificate - Lot A999').call()}")

    title("SUMMARY")
    print(f"  Total batches: {c.functions.batchCount().call()}")
    print(f"  ETH left in escrow: {eth(c.functions.getEscrowBalance().call())}")
    print(f"  Contract address (use 'At Address' in Remix): {receipt.contractAddress}")


if __name__ == "__main__":
    main()
