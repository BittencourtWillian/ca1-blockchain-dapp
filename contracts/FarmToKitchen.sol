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
        uint256 tempReadings;     // number of temperature readings recorded
        int16   highestTempC;     // highest temperature recorded during transport
        bool    coldChainBroken;  // true if any reading was above maxTempC
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
    event TemperatureRecorded(uint256 indexed id, int16 temperatureC, bool withinLimit);
    event BatchDelivered(uint256 indexed id);
    event DeliveryAccepted(uint256 indexed id, address indexed supplier, uint256 amountPaid);
    event DeliveryRejected(uint256 indexed id, address indexed kitchen, uint256 amountRefunded,
                           bool coldChainBroken);
    event BatchRecalled(uint256 indexed id, string reason);

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

    modifier onlyBatchSupplier(uint256 _id) {
        require(msg.sender == batches[_id].supplier, "Only the supplier of this batch can do this");
        _;
    }

    modifier onlyBatchKitchen(uint256 _id) {
        require(msg.sender == batches[_id].kitchen, "Only the kitchen of this batch can do this");
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

    /// STEP 1 - Kitchen (receiver) places an order and sends the payment, which stays in escrow
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

    /// STEP 2 - Supplier (sender) dispatches the batch and records its traceability data
    function dispatchBatch(
        uint256 _id,
        string calldata _origin,
        string calldata _lotCode,
        uint256 _expiryDate,
        bytes32 _certificateHash
    ) external batchExists(_id) onlyBatchSupplier(_id) {
        Batch storage b = batches[_id];
        require(b.status == Status.Ordered, "Batch is not waiting for dispatch");
        require(_expiryDate > block.timestamp, "Product is already expired");

        b.origin          = _origin;
        b.lotCode         = _lotCode;
        b.expiryDate      = _expiryDate;
        b.certificateHash = _certificateHash;
        b.status          = Status.Dispatched;

        emit BatchDispatched(_id, _origin, _lotCode, _certificateHash);
    }

    /// STEP 3 - Supplier records a temperature reading during transport
    ///          (in a real system this would come from an IoT sensor through an oracle)
    function recordTemperature(uint256 _id, int16 _temperatureC)
        external batchExists(_id) onlyBatchSupplier(_id)
    {
        Batch storage b = batches[_id];
        require(b.status == Status.Dispatched, "Batch is not in transit");

        if (b.tempReadings == 0 || _temperatureC > b.highestTempC) {
            b.highestTempC = _temperatureC;
        }
        b.tempReadings++;

        bool withinLimit = _temperatureC <= b.maxTempC;
        if (!withinLimit) {
            b.coldChainBroken = true;   // cannot be undone: the record is permanent
        }

        emit TemperatureRecorded(_id, _temperatureC, withinLimit);
    }

    /// STEP 4 - Supplier confirms the batch arrived at the kitchen
    function markDelivered(uint256 _id) external batchExists(_id) onlyBatchSupplier(_id) {
        Batch storage b = batches[_id];
        require(b.status == Status.Dispatched, "Batch is not in transit");
        require(b.tempReadings > 0, "At least one temperature reading is required");

        b.status = Status.Delivered;
        emit BatchDelivered(_id);
    }

    /// STEP 5 - Kitchen inspects the delivery and accepts or rejects it.
    ///   - accepted AND cold chain respected -> payment released to the supplier
    ///   - rejected OR cold chain broken     -> payment refunded to the kitchen
    function confirmDelivery(uint256 _id, bool _accept)
        external batchExists(_id) onlyBatchKitchen(_id)
    {
        Batch storage b = batches[_id];
        require(b.status == Status.Delivered, "Batch has not been delivered yet");

        uint256 amount = b.payment;
        b.payment = 0;   // update state BEFORE sending ETH (protection against re-entrancy)

        if (_accept && !b.coldChainBroken) {
            b.status = Status.Accepted;
            (bool ok, ) = payable(b.supplier).call{value: amount}("");
            require(ok, "Payment to supplier failed");
            emit DeliveryAccepted(_id, b.supplier, amount);
        } else {
            b.status = Status.Rejected;
            (bool ok, ) = payable(b.kitchen).call{value: amount}("");
            require(ok, "Refund to kitchen failed");
            emit DeliveryRejected(_id, b.kitchen, amount, b.coldChainBroken);
        }
    }

    /// Regulator recalls a batch (e.g. contamination found).
    /// If the payment is still in escrow, it is refunded to the kitchen.
    function recallBatch(uint256 _id, string calldata _reason)
        external onlyRegulator batchExists(_id)
    {
        Batch storage b = batches[_id];
        require(b.status != Status.Recalled, "Batch already recalled");

        b.status = Status.Recalled;
        uint256 amount = b.payment;
        if (amount > 0) {
            b.payment = 0;
            (bool ok, ) = payable(b.kitchen).call{value: amount}("");
            require(ok, "Refund to kitchen failed");
        }

        emit BatchRecalled(_id, _reason);
    }

    // ---------------------------------------------------------------
    // 6. VIEW / HELPER FUNCTIONS (free to call, no transaction)
    // ---------------------------------------------------------------

    /// Anyone (inspector, customer) can read the full record of a batch
    function getBatch(uint256 _id) external view batchExists(_id) returns (Batch memory) {
        return batches[_id];
    }

    /// Calculates the Keccak-256 hash of a document text (e.g. a certificate).
    /// In a real system the file is stored off-chain and only this hash goes on-chain.
    function hashDocument(string calldata _document) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_document));
    }

    /// Checks if a document matches the hash stored for a batch (tamper detection)
    function verifyCertificate(uint256 _id, string calldata _document)
        external view batchExists(_id) returns (bool)
    {
        return keccak256(abi.encodePacked(_document)) == batches[_id].certificateHash;
    }

    /// Total ETH currently held in escrow by the contract
    function getEscrowBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
