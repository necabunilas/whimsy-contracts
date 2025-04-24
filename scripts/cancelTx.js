require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  const [wallet] = await ethers.getSigners();
  const provider = ethers.provider;

  // 🧾 Step 1: Get the pending nonce
  const nonce = await provider.getTransactionCount(wallet.address, "pending");
  console.log("🧾 Using nonce:", nonce);

  // 💰 Step 2: Get current gas settings
  const feeData = await provider.getFeeData();
  const maxFeePerGas = feeData.maxFeePerGas * 2n;
  const maxPriorityFeePerGas = feeData.maxPriorityFeePerGas * 2n;

  // 🧨 Step 3: Send a 0 ETH tx to yourself with the same nonce
  const tx = await wallet.sendTransaction({
    to: wallet.address,
    value: 0,
    nonce,
    maxFeePerGas,
    maxPriorityFeePerGas,
  });

  console.log("🔄 Sent cancel tx:", tx.hash);
  await tx.wait();
  console.log("✅ Cancel tx mined");
}

main().catch((error) => {
  console.error("❌ Error:", error);
  process.exit(1);
});
