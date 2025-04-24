// scripts/createPropertyToken.js
const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const factoryAddress = "0x83C6b904C163B488069ad65405448Be53CfA3D78";
  const seller         = "0x2618318ccd4192F26eF4577f29Ad508300CBD1f4";

  const [caller] = await ethers.getSigners();

  const Factory = await ethers.getContractFactory("PropertyTokenFactory", caller);
  const factory = Factory.attach(factoryAddress);

  // 🏗 Parameters
  const initialSupply = ethers.parseUnits("200000", 6); // 200,000 tokens at 6 decimals
  const tokenPrice    = ethers.parseUnits("1", 6); // 1 USDC
  const targetSellerOwnership = ethers.parseUnits("40000", 6); // 20% of 200k

  console.log("📤 Creating property token...");
  const tx = await factory.createIPropertyToken(
    "Whimsy Property",
    "WHIMZ",
    initialSupply,
    seller,
    targetSellerOwnership,
    tokenPrice
  );
  const receipt = await tx.wait();

  const iface = factory.interface;
  const event = receipt.logs.map(log => {
    try { return iface.parseLog(log); } catch { return null; }
  }).find(e => e?.name === "NewProperty");

  if (!event) {
    console.error("❌ Failed to deploy property token.");
    return;
  }

  const tokenAddress = event.args.tokenAddress;
  const propertyId = await factory.propertyCount();

  console.log("✅ PropertyToken deployed!");
  console.log("🏠 Token Address:", tokenAddress);
  console.log("🆔 Property ID:", propertyId.toString());
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
