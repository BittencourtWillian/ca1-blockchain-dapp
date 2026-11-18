// remix_place_order.js
// Runs INSIDE Remix (right-click the file > Run).
// The kitchen (Account 3) places an order and sends 1 ETH, which is held in escrow
// by the FarmToKitchen contract. Used because the Remix UI Value field is not
// applied to payable function calls in the current Remix version.

const CONTRACT_ADDRESS = "PASTE_YOUR_CONTRACT_ADDRESS_HERE";

(async () => {
  try {
    // Works with ethers v5 or v6 (depending on the Remix version)
    const v6 = !!ethers.BrowserProvider;
    const provider = v6 ? new ethers.BrowserProvider(web3Provider)
                        : new ethers.providers.Web3Provider(web3Provider);
    const parseEther  = v6 ? ethers.parseEther  : ethers.utils.parseEther;
    const formatEther = v6 ? ethers.formatEther : ethers.utils.formatEther;

    const kitchen  = await provider.getSigner(2);                    // Account 3 = kitchen (receiver)
    const supplier = await (await provider.getSigner(1)).getAddress(); // Account 2 = supplier (sender)

    const abi = [
      "function placeOrder(address _supplier, string _product, uint256 _quantityKg, int16 _maxTempC) payable returns (uint256)",
      "function batchCount() view returns (uint256)",
      "function getEscrowBalance() view returns (uint256)"
    ];
    const contract = new ethers.Contract(CONTRACT_ADDRESS, abi, kitchen);

    console.log("Kitchen placing order with 1 ETH...");
    const tx = await contract.placeOrder(supplier, "Chicken breast", 20, 5, { value: parseEther("1") });
    await tx.wait();

    console.log("Order placed! Tx hash:", tx.hash);
    console.log("Batch count:", (await contract.batchCount()).toString());
    console.log("Escrow balance:", formatEther(await contract.getEscrowBalance()), "ETH");
  } catch (err) {
    console.log("Error:", err.message);
  }
})();
