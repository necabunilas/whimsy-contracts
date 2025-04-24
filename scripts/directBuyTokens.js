// scripts/buyTokens.js
const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const FACTORY     = "0x7115F45B061161A6eCe9e9Bd4cDda5449F5e36B9";
  const PROPERTY    = 1;
  const USDC        = "0xCD2FB11F22FAE9c1c455C670e42F0Af5a5De391a";
  const AMOUNT      = 30n;

  const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC);
  const buyer    = new ethers.Wallet(process.env.BUYER_PRIVATE_KEY, provider);
  console.log("🧾 Buyer:", buyer.address);

  const Factory = await ethers.getContractFactory("PropertyTokenFactory");
  const factory = Factory.attach(FACTORY).connect(buyer);

  const tokenAddr = await factory.getIPropertyToken(PROPERTY);
  console.log("🏠 PropertyToken @", tokenAddr);

  const usdc = new ethers.Contract(
    USDC,
    [
      "function approve(address,uint256) returns (bool)",
      "function balanceOf(address) view returns(uint256)",
      "function decimals() view returns (uint8)",
      "function allowance(address owner, address spender) view returns (uint256)"
    ],
    buyer
  );

  const DEC = await usdc.decimals();
  const pricePerToken = ethers.parseUnits("1", DEC);
  const totalCost     = pricePerToken * AMOUNT;

  console.log("💵 Buying", AMOUNT.toString(), "tokens at", ethers.formatUnits(pricePerToken, DEC), "USDC each");

  // --- Balance Check ---
  const buyerBalance = await usdc.balanceOf(buyer.address);
  if (buyerBalance < totalCost) {
    console.error("❌ Not enough USDC! Buyer has:", ethers.formatUnits(buyerBalance, DEC));
    return;
  } else {
    console.log("✅ Buyer balance:", ethers.formatUnits(buyerBalance, DEC));
  }

  // --- Approve ---
  console.log("🔐 Approving PropertyToken to pull USDC...");
  const approveTx = await usdc.approve(tokenAddr, totalCost);
  await approveTx.wait();
  console.log("✅ Approved.");

  // --- Allowance Check ---
  const allowance = await usdc.allowance(buyer.address, tokenAddr);
  console.log("🔎 Allowance set to:", ethers.formatUnits(allowance, DEC));
  if (allowance < totalCost) {
    console.error("❌ Allowance is insufficient!");
    return;
  }

  // --- Agree Disclaimer ---
  console.log("📜 Agreeing to disclaimer...");
  const discTx = await factory.agreeDisclaimer(PROPERTY);
  await discTx.wait();
  console.log("✅ Disclaimer agreed.");

  // --- Buy Tokens ---
  const nonce = await provider.getTransactionCount(buyer.address, "pending");
  console.log(`🛒 Buying ${AMOUNT} tokens…`);
  try {
    const buyTx = await factory.buyTokens(PROPERTY, AMOUNT, {
      nonce,
      maxPriorityFeePerGas: ethers.parseUnits("2", "gwei"),
      maxFeePerGas:         ethers.parseUnits("100", "gwei")
    });
    const receipt = await buyTx.wait();
    console.log("✅ Tokens purchased. Tx hash:", receipt.hash);
  } catch (err) {
    console.error("❌ buyTokens reverted:", err);
    return;
  }

  // --- Verify Buyer Token Balance ---
  const Token = await ethers.getContractFactory("PropertyToken");
  const token = Token.attach(tokenAddr).connect(buyer);
  const tokenBalance = await token.balanceOf(buyer.address);
  console.log("🪙 Buyer token balance:", ethers.formatUnits(tokenBalance, DEC));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
