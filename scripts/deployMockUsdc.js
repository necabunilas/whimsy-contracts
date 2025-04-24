const { ethers } = require("hardhat");

async function main() {
  const buyerAddress = "0xC8F344b9e5726556a97361a4E763aB301D41E30e"; // 🔁 Replace with your buyer's Sepolia address
  const mintAmount = ethers.parseUnits("100000000", 6); // 1 million USDC (6 decimals)

  // Deploy MockERC20
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const usdc = await MockERC20.deploy();
  await usdc.waitForDeployment();

  console.log("✅ Mock USDC deployed at:", await usdc.getAddress());

  // Mint to buyer
  const mintTx = await usdc.mint(buyerAddress, mintAmount);
  await mintTx.wait();

  console.log(`💸 Minted ${ethers.formatUnits(mintAmount, 6)} USDC to ${buyerAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
