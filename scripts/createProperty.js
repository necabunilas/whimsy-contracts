const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const factoryAddress = "0xf08313e987f5AB12A629cD6bce7300fdF593F239";
  const seller = "0xA845cc8A1DF843a2D872A7D9F27eC330a068fcb8";

  const [caller] = await ethers.getSigners(); // This must match the seller

  const Factory = await ethers.getContractFactory("PropertyTokenFactory", caller);
  const factory = Factory.attach(factoryAddress);

  const tx = await factory.createIPropertyToken("NewProperty", "NPT", 1000, seller);
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

  console.log("🏠 Token deployed at:", tokenAddress);
  console.log("📦 Property ID:", propertyId.toString());

  // Optionally set sale params
  await factory.setSaleParameters(propertyId, 700, 1, 300);
  console.log("✅ Sale parameters set.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
