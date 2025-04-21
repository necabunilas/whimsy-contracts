const { ethers } = require("ethers"); // use ethers instead of hardhat here
require("dotenv").config();

async function main() {
  const factoryAddress = "0xf08313e987f5AB12A629cD6bce7300fdF593F239"; // Base Sepolia
  const propertyId = 5;
  const tokenOwner = "0x2618318ccd4192F26eF4577f29Ad508300CBD1f4";

  // ✅ Connect to Base Sepolia using your whimsy private key
  const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC);
  const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

  console.log("🔐 Caller:", signer.address);

  const factoryABI = [
    "function getIPropertyToken(uint256) view returns (address)",
    "function clawback(uint256,address)",
  ];

  const tokenABI = ["function balanceOf(address) view returns (uint256)"];

  const factory = new ethers.Contract(factoryAddress, factoryABI, signer);

  const tokenAddress = await factory.getIPropertyToken(propertyId); // should now work
  const token = new ethers.Contract(tokenAddress, tokenABI, provider);

  const balanceBefore = await token.balanceOf(tokenOwner);
  console.log(`📊 Token balance before clawback: ${balanceBefore.toString()}`);

  if (balanceBefore === 0n) {
    console.log("⚠️ No tokens to clawback.");
    return;
  }

  console.log("🚨 Clawing back...");
  const tx = await factory.clawback(propertyId, tokenOwner);
  const receipt = await tx.wait();
  console.log("✅ Clawback TX:", receipt.hash);

  const balanceAfter = await token.balanceOf(tokenOwner);
  const ownerBalance = await token.balanceOf(signer.address);

  console.log(`📉 Token balance after: ${balanceAfter.toString()}`);
  console.log(`🏦 Factory owner token balance: ${ownerBalance.toString()}`);
}

main().catch((err) => {
  console.error("❌ Error:", err);
  process.exit(1);
});
