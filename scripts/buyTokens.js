// scripts/buyTokens.js
require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  // ── CONFIG ─────────────────────────────────────────────
  const FACTORY_ADDR    = "0x8C8F4662c6eDd77691365101247317dDD6e3Bf25"; // your factory
  const PROPERTY_ID     = 2;                                      // the property you created
  const USDC_ADDR       = "0xCD2FB11F22FAE9c1c455C670e42F0Af5a5De391a"; // your mock‑USDC
  const HUMAN_TOKENS    = 50n;                                    // “30” tokens to buy

  // ── SETUP ──────────────────────────────────────────────
  const rpc     = process.env.BASE_RPC;
  const provider = new ethers.JsonRpcProvider(rpc);
  const buyer    = new ethers.Wallet(process.env.BUYER_PRIVATE_KEY, provider);
  console.log("🧾 Buyer:", buyer.address);

  // ── ATTACH FACTORY & TOKEN ─────────────────────────────
  const Factory = await ethers.getContractFactory("PropertyTokenFactory");
  const factory = Factory.attach(FACTORY_ADDR).connect(buyer);

  const tokenAddr = await factory.getIPropertyToken(PROPERTY_ID);
  console.log("🏠 PropertyToken @", tokenAddr);

  const Token = await ethers.getContractFactory("PropertyToken");
  const token = Token.attach(tokenAddr).connect(buyer);

  // ── USDC HELPER ────────────────────────────────────────
  const usdc = new ethers.Contract(
    USDC_ADDR,
    [
      "function decimals() view returns (uint8)",
      "function approve(address,uint256) returns (bool)",
      "function balanceOf(address) view returns (uint256)"
    ],
    buyer
  );
  const DEC = await usdc.decimals();   // should be 6

  // ── PRICING & AMOUNTS ─────────────────────────────────
  const pricePerToken = await token.tokenPrice();  // atomic USDC per token (e.g. 1e6)
  console.log("🔖 pricePerToken:", ethers.formatUnits(pricePerToken, DEC), "USDC");

  // human→atomic: 30 tokens → 30×10⁶ = 30000000
  const ATOMIC_AMT = HUMAN_TOKENS * (10n ** BigInt(DEC));
  // totalCost = pricePerToken × HUMAN_TOKENS
  const TOTAL_COST = pricePerToken * HUMAN_TOKENS;
  console.log("🔖 humanTokens:", HUMAN_TOKENS.toString());
  console.log("🔖 atomicTokens:", ATOMIC_AMT.toString());
  console.log("🔖 totalCostUSDC:", ethers.formatUnits(TOTAL_COST, DEC));

  // ── 1) APPROVE PropertyToken to pull USDC ───────────────
  console.log("🔐 Approving token‑contract to pull USDC…");
  let tx = await usdc.approve(tokenAddr, TOTAL_COST);
  await tx.wait();
  console.log("   ↳ approved");

  // ── 2) AGREE to the disclaimer ──────────────────────────
  console.log("📜 Agreeing disclaimer…");
  tx = await factory.agreeDisclaimer(PROPERTY_ID);
  await tx.wait();
  console.log("   ↳ disclaimer agreed");

  // ── 3) BUY TOKENS ──────────────────────────────────────
  console.log(`🛒 Buying ${HUMAN_TOKENS} tokens (atomic ${ATOMIC_AMT})…`);
  tx = await factory.buyTokens(PROPERTY_ID, ATOMIC_AMT, {
    gasLimit: 200_000
  });
  const receipt = await tx.wait();
  console.log("   ↳ buyTokens mined in block", receipt.blockNumber);

  // ── 4) VERIFY BALANCE ──────────────────────────────────
  const newBal = await token.balanceOf(buyer.address);
  console.log("✅ Buyer now has (atomic):", newBal.toString());
  console.log("   which is", ethers.formatUnits(newBal, DEC), "whole tokens");

  // optional: show USDC leftover in token contract
  const leftover = await usdc.balanceOf(tokenAddr);
  console.log("🏦 Token‑contract USDC balance:", ethers.formatUnits(leftover, DEC));
}

main().catch(console.error);
