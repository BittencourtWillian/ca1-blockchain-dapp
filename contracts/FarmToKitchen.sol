// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title FarmToKitchen - Food traceability between a supplier and a restaurant kitchen
/// @notice The contract is the trusted middle layer: it records every batch of food
///         and holds the kitchen's payment in escrow until the delivery is confirmed.
contract FarmToKitchen {

    // ---------------------------------------------------------------
    // 1. DATA TYPES
    // ---------------------------------------------------------------

    /// Life cycle of a batch
    enum Status { Ordered, Dispatched, Delivered, Accepted, Rejected, Recalled }

    /// All information about one batch of food
    struct Batch {
        uint256 id;
        address kitchen;          // receiver (restaurant) - places the order and pays
        address supplier;         // sender - dispatches the food
        string  product;          // e.g. "Chicken breast"
        uint256 quantityKg;
        int16   maxTempC;         // maximum allowed temperature (e.g. 5 chilled, -18 frozen)
        uint256 payment;          // amount (wei) held in escrow by the contract
        string  origin;           // farm / producer
        string  lotCode;          // supplier lot code
        uint256 expiryDate;       // unix timestamp
        bytes32 certificateHash;  // Keccak-256 hash of the certificate stored off-chain
        Status  status;
        uint256 createdAt;
    }

    // ---------------------------------------------------------------
    // 2. STATE VARIABLES
    // ---------------------------------------------------------------

    address public regulator;                     // food-safety authority / admin
    uint256 public batchCount;                    // total number of batches
    mapping(uint256 => Batch) private batches;    // batch id => batch
    mapping(address => bool) public isSupplier;   // registered (trusted) suppliers

    // ---------------------------------------------------------------
    // 3. EVENTS (permanent audit trail)
    // ---------------------------------------------------------------

    event SupplierRegistered(address indexed supplier);
    event OrderPlaced(uint256 indexed id, address indexed kitchen, address indexed supplier,
                      string product, uint256 payment);
    event BatchDispatched(uint256 indexed id, string origin, string lotCode, bytes32 certificateHash);

    // ---------------------------------------------------------------
    // 4. MODIFIERS (access control)
    // ---------------------------------------------------------------

    modifier onlyRegulator() {
        require(msg.sender == regulator, "Only the regulator can do this");
        _;
    }

    modifier batchExists(uint256 _id) {
        require(_id > 0 && _id <= batchCount, "Batch does not exist");
        _;
    }

    // ---------------------------------------------------------------
    // 5. FUNCTIONS
    // ---------------------------------------------------------------

    /// The account that deploys the contract becomes the regulator
    constructor() {
        regulator = msg.sender;
    }

    /// Regulator approves a supplier so it can dispatch food
    function registerSupplier(address _supplier) external onlyRegulator {
        require(_supplier != address(0), "Invalid address");
        require(!isSupplier[_supplier], "Supplier already registered");
        isSupplier[_supplier] = true;
        emit SupplierRegistered(_supplier);
    }

    /// Kitchen (receiver) places an order and sends the payment, which stays in escrow
    function placeOrder(
        address _supplier,
        string calldata _product,
        uint256 _quantityKg,
        int16 _maxTempC
    ) external payable returns (uint256) {
        require(isSupplier[_supplier], "Supplier is not registered");
        require(msg.value > 0, "Payment is required");
        require(_quantityKg > 0, "Quantity must be greater than zero");

        batchCount++;
        Batch storage b = batches[batchCount];
        b.id         = batchCount;
        b.kitchen    = msg.sender;
        b.supplier   = _supplier;
        b.product    = _product;
        b.quantityKg = _quantityKg;
        b.maxTempC   = _maxTempC;
        b.payment    = msg.value;
        b.status     = Status.Ordered;
        b.createdAt  = block.timestamp;

        emit OrderPlaced(batchCount, msg.sender, _supplier, _product, msg.value);
        return batchCount;
    }

    /// Supplier (sender) dispatches the batch and records its traceability data
    function dispatchBatch(
        uint256 _id,
        string calldata _origin,
        string calldata _lotCode,
        uint256 _expiryDate,
        bytes32 _certificateHash
    ) external batchExists(_id) {
        Batch storage b = batches[_id];
        require(msg.sender == b.supplier, "Only the supplier of this order can dispatch");
        require(b.status == Status.Ordered, "Batch is not waiting for dispatch");
        require(_expiryDate > block.timestamp, "Product is already expired");

        b.origin          = _origin;
        b.lotCode         = _lotCode;
        b.expiryDate      = _expiryDate;
        b.certificateHash = _certificateHash;
        b.status          = Status.Dispatched;

        emit BatchDispatched(_id, _origin, _lotCode, _certificateHash);
    }

    /// Anyone (inspector, customer) can read the full record of a batch
    function getBatch(uint256 _id) external view batchExists(_id) returns (Batch memory) {
        return batches[_id];
    }

    /// Helper: calculates the Keccak-256 hash of a document text (e.g. a certificate).
    /// In a real system the file is stored off-chain and only this hash goes on-chain.
    function hashDocument(string calldata _document) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_document));
    }

    /// Total ETH currently held in escrow by the contract
    function getEscrowBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
