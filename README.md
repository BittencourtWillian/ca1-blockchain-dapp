# CA1 – FarmToKitchen: Blockchain Food Traceability DApp

**Module:** Blockchain
**Assessment:** CA1
**Student name:** _<Willian Cesar Lino Bittencourt>_
**Student number:** _<2024419>_
**GitHub repository:** _<https://github.com/BittencourtWillian/ca1-blockchain-dapp.git>_
**Link Video of Poster** <https://drive.google.com/drive/folders/1sdmuRW02Dql91I_96Y-R-wKIjcG5r3wX?usp=sharing>

## 1. Overview

**Scenario:** Food Traceability – from the supplier to the restaurant kitchen.

FarmToKitchen is a decentralised application (DApp) in which a smart contract acts as the
**trusted middle layer** between a **supplier (sender)** and a **restaurant kitchen (receiver)**.
It records every batch of food (origin, lot code, expiry, certificate hash, transport
temperatures) and holds the kitchen's payment in **escrow** until the delivery is confirmed:

- Delivery accepted and cold chain respected → payment released to the supplier
- Delivery rejected **or cold chain broken** → automatic refund to the kitchen
- Batch recalled by the regulator → refund to the kitchen

Full analysis, business model, UML design and cryptography: [`docs/analysis.md`](docs/analysis.md)

## 2. Technology Stack

| Tool             | Purpose                                                 |
| ---------------- | ------------------------------------------------------- |
| Solidity 0.8.20  | Smart contract (`contracts/FarmToKitchen.sol`)          |
| Remix IDE        | Writing, compiling, deploying and testing the contract  |
| Ganache          | Local Ethereum blockchain (10 test accounts)            |
| Python + web3.py | Deploys the contract and runs end-to-end scenarios      |
| py-solc-x        | Compiles the Solidity contract from Python              |
| Shell script     | Environment check and one-command execution of the demo |

## 3. Repository Structure

```
.
├── contracts/
│   └── FarmToKitchen.sol        # Smart contract
├── scripts/
│   ├── check_env.sh             # Checks Python, Node, Ganache and libraries
│   ├── run_all.sh               # Runs the whole demo with one command
│   ├── farm_to_kitchen.py       # Deploy + scenarios A, B, C on Ganache
│   └── remix_place_order.js     # Remix script (payable call workaround)
├── docs/
│   ├── analysis.md              # Task 1 – analysis, design, cryptography
│   ├── screenshots/             # Remix + Ganache test evidence
│   └── diagrams/
├── poster/                      # PowerPoint poster
└── README.md
```

## 4. Smart Contract

**Roles:** Regulator (deploys, approves suppliers, recalls) · Supplier (sender) · Kitchen (receiver)

**Batch life cycle:** `Ordered → Dispatched → Delivered → Accepted | Rejected` (and `Recalled` at any time)

| Function                                                            | Caller    | Description                                                   |
| ------------------------------------------------------------------- | --------- | ------------------------------------------------------------- |
| `registerSupplier`                                                  | Regulator | Approves a trusted supplier                                   |
| `placeOrder` _(payable)_                                            | Kitchen   | Creates an order; payment is held in escrow                   |
| `dispatchBatch`                                                     | Supplier  | Origin, lot code, expiry date, certificate hash               |
| `recordTemperature`                                                 | Supplier  | Transport reading; above the limit → `coldChainBroken = true` |
| `markDelivered`                                                     | Supplier  | Confirms arrival (requires at least one reading)              |
| `confirmDelivery`                                                   | Kitchen   | Accept → pays supplier; reject or broken cold chain → refund  |
| `recallBatch`                                                       | Regulator | Recalls a batch and refunds any escrowed payment              |
| `getBatch`, `verifyCertificate`, `hashDocument`, `getEscrowBalance` | Anyone    | Read-only traceability and verification                       |

**Security features:** role-based access control (`modifier`), input validation (`require`),
checks-effects-interactions pattern against re-entrancy, permanent audit trail (`event`),
ECDSA-signed transactions (`msg.sender`) and Keccak-256 document hashing.

## 5. How to Run

### Option A – Remix IDE

1. Open [remix.ethereum.org](https://remix.ethereum.org), create `FarmToKitchen.sol` and paste the contract.
2. Compile with Solidity 0.8.20+.
3. Deploy with Account 1 (regulator), then test `registerSupplier`, `hashDocument`, access-control errors, etc.

> Note: in the current Remix version the _Value_ field is not applied to payable function calls,
> so the payable flow (`placeOrder`) is demonstrated with Python + Ganache (Option B).

### Option B – Ganache + Python (full flow with payments)

Requirements: Node.js, Python 3, Git Bash (Windows).

```bash
npm install -g ganache
pip install web3 py-solc-x
```

Terminal 1 – start the local blockchain:

```bash
ganache --wallet.deterministic
```

Terminal 2 – run everything with one command:

```bash
bash scripts/run_all.sh
```

## 6. Test Results (Ganache)

| Test                                                                 | Result                                                           |
| -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Order to an unregistered supplier                                    | Rejected – _"Supplier is not registered"_                        |
| **Scenario A** – temperatures 3 °C and 4 °C, kitchen accepts         | Status **Accepted**, supplier receives 1 ETH                     |
| **Scenario B** – 9 °C recorded (limit 5 °C), kitchen tries to accept | Status **Rejected**, 1 ETH automatically refunded to the kitchen |
| **Scenario C** – regulator recall (_"Listeria found at the farm"_)   | Status **Recalled**, 1 ETH refunded to the kitchen               |
| Certificate verification                                             | Original document **True**, tampered document **False**          |
| Escrow balance at the end                                            | **0 ETH** – no funds locked                                      |

Remix tests: compilation, deployment, supplier registration, duplicate registration rejected,
access control (_"Only the regulator can do this"_), _"Batch does not exist"_, _"Payment is required"_,
and Keccak-256 avalanche effect (one character changed → completely different hash).
Evidence in `docs/screenshots/`.

## 7. Deliverables

- [x] DApp – Solidity contract + Python and Shell scripts
- [ ] PowerPoint poster (max. 700 words)
- [ ] Video presentation (max. 4 minutes, own voice)
- [ ] CCT Assessment Cover Page

## 8. References

See [`docs/analysis.md`](docs/analysis.md#8-references-harvard) (Harvard style).
