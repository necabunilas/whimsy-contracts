// scripts/endSale.js
require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  const PROPERTY_ID = 1; // 🏠 Update this to the property ID you want to end
  const FACTORY_ADDRESS = "0x83C6b904C163B488069ad65405448Be53CfA3D78"; // 🔁 Replace with your deployed factory address

  const [owner] = await ethers.getSigners();
  console.log("👤 Caller:", owner.address);

  const Factory = await ethers.getContractFactory("PropertyTokenFactory", owner);
  const factory = Factory.attach(FACTORY_ADDRESS);

  // 🔄 Call endSaleEarly
  console.log("⏹️ Calling endSaleEarly for property ID:", PROPERTY_ID);
  const tx = await factory.endSaleEarly(PROPERTY_ID);
  await tx.wait();

  console.log("✅ Sale ended successfully for property ID:", PROPERTY_ID);
}

main().catch((error) => {
  console.error("❌ Script failed:", error);
  process.exit(1);
});
