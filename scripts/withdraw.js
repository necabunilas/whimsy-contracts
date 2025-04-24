// scripts/withdrawUsdc.js
require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  // ── CONFIG ─────────────────────────────────────────────
  const FACTORY_ADDR  = "0x83C6b904C163B488069ad65405448Be53CfA3D78"; // your factory
  const PROPERTY_ID   = 1;                                      // property id
  const SELLER_ADDR   = "0x2618318ccd4192F26eF4577f29Ad508300CBD1f4"; // seller
  const USDC_ADDR     = "0xCD2FB11F22FAE9c1c455C670e42F0Af5a5De391a"; // USDC token

  // ── SETUP OWNER/OPERATOR SIGNER & FACTORY ───────────────────
  const [caller] = await ethers.getSigners();
  console.log("🔐 Caller (must be factory owner/operator):", caller.address);

  const Factory = await ethers.getContractFactory("PropertyTokenFactory", caller);
  const factory = Factory.attach(FACTORY_ADDR);

  // ── LOOK UP THE PROPERTY‐TOKEN & USDC CONTRACT ──────────────
  const tokenAddr = await factory.getIPropertyToken(PROPERTY_ID);
  console.log("🏠 PropertyToken @", tokenAddr);

  const usdc = new ethers.Contract(
    USDC_ADDR,
    [
      "function balanceOf(address) view returns (uint256)",
      "function decimals()  view returns (uint8)"
    ],
    ethers.provider
  );

  // ── FETCH DECIMALS & PRE‐WITHDRAW BALANCES ───────────────────
  const DEC             = await usdc.decimals();
  const tokenUsdcBefore = await usdc.balanceOf(tokenAddr);
  const sellerUsdcBefore= await usdc.balanceOf(SELLER_ADDR);

  console.log(`🏦 Token USDC before:  ${ethers.formatUnits(tokenUsdcBefore, DEC)} USDC`);
  console.log(`💰 Seller USDC before: ${ethers.formatUnits(sellerUsdcBefore, DEC)} USDC`);

  if (tokenUsdcBefore == 0) {
    console.log("⚠️  No USDC to withdraw.");
    return;
  }

  // ── WITHDRAW USDC ───────────────────────────────────────────
  console.log("🔄 Calling factory.withdrawPayment...");
  try {
    const tx = await factory.withdrawPayment(PROPERTY_ID, { gasLimit: 200_000 });
    const receipt = await tx.wait();
    console.log("✅ Withdraw tx hash:", receipt.transactionHash);
  } catch (err) {
    console.error("❌ Withdraw failed:", err.reason || err.message);
    return;
  }  

  // ── POST‐WITHDRAW BALANCES & DELTA ───────────────────────────
  const tokenUsdcAfter  = await usdc.balanceOf(tokenAddr);
  const sellerUsdcAfter = await usdc.balanceOf(SELLER_ADDR);
  const delta           = sellerUsdcAfter - sellerUsdcBefore;

  console.log(`🏦 Token USDC after:   ${ethers.formatUnits(tokenUsdcAfter, DEC)} USDC`);
  console.log(`💰 Seller USDC after:  ${ethers.formatUnits(sellerUsdcAfter, DEC)} USDC`);
  console.log(`📈 USDC transferred:   ${ethers.formatUnits(delta, DEC)} USDC`);
}

main()
  .catch((err) => {
    console.error("❌ Script failed:", err);
    process.exit(1);
  });
