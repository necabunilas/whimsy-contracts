const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const factoryAddress = "0xf08313e987f5AB12A629cD6bce7300fdF593F239";
  const propertyId = 5;

  // ───── Setup buyer wallet ─────
  const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC);
  const buyer = new ethers.Wallet(process.env.BUYER_PRIVATE_KEY, provider);
  console.log("🧾 Using BUYER wallet:", buyer.address);

  // ───── Attach factory as buyer ─────
  const Factory = await ethers.getContractFactory("PropertyTokenFactory");
  const factory = Factory.attach(factoryAddress).connect(buyer);

  // ───── Log balance before ─────
  const balBefore = await provider.getBalance(buyer.address);
  console.log(`💰 Balance before: ${ethers.formatEther(balBefore)} ETH`);

  // 1️⃣ Agree to disclaimer
  console.log("✅ Agreeing to disclaimer...");
  const agreeTx = await factory.agreeDisclaimer(propertyId);
  await agreeTx.wait();
  console.log(`📜 Disclaimer agreed. Tx hash: ${agreeTx.hash}`);

  // 2️⃣ Buy tokens
  const amount = 30;
  console.log(`💸 Buying ${amount} tokens (paying ${amount} wei)...`);

  const nonce = await provider.getTransactionCount(buyer.address, "latest");
  const maxPriorityFeePerGas = ethers.parseUnits("2", "gwei");
  const maxFeePerGas = ethers.parseUnits("50", "gwei");

  const buyTx = await factory.buyTokens(propertyId, amount, {
    value: amount,
    nonce,
    maxPriorityFeePerGas,
    maxFeePerGas,
  });

  await buyTx.wait();
  console.log(`✅ Bought ${amount} tokens.`);
  console.log(`📦 Transaction hash: ${buyTx.hash}`);

  // ───── Log balance after ─────
  const balAfter = await provider.getBalance(buyer.address);
  console.log(`💰 Balance after:  ${ethers.formatEther(balAfter)} ETH`);

  const spent = balBefore - balAfter;
  console.log(`🧾 Total spent:    ${ethers.formatEther(spent)} ETH`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
