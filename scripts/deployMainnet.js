// scripts/deploy.js
require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  // ── CONFIG ─────────────────────────────────────────────
  const WHIMSY_ADDRESS = process.env.WHIMSY_ADDRESS;
  const USDC_ADDRESS   = process.env.USDC_ADDRESS;

  if (!WHIMSY_ADDRESS || !USDC_ADDRESS)
    throw new Error("Please set WHIMSY_ADDRESS and USDC_ADDRESS in .env");

  // ── Deploy Factory ─────────────────────────────────────
  console.log("📦 Deploying PropertyTokenFactory…");
  const Factory = await ethers.getContractFactory("PropertyTokenFactory");
  const factory = await Factory.deploy(WHIMSY_ADDRESS, USDC_ADDRESS);
  await factory.waitForDeployment();
  console.log("✅ Factory deployed @", factory.target);

  console.log("\nℹ️  You can now use this factory to create PropertyTokens.");
  console.log("   Run: npx hardhat run scripts/createPropertyToken.js --network base");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
