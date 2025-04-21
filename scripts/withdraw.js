const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const factoryAddress = "0xf08313e987f5AB12A629cD6bce7300fdF593F239";
  const propertyId = 5;
  const seller = "0xA845cc8A1DF843a2D872A7D9F27eC330a068fcb8";

  const [caller] = await ethers.getSigners(); // Must be seller/owner
  const Factory = await ethers.getContractFactory("PropertyTokenFactory", caller);
  const factory = Factory.attach(factoryAddress);

  // Get the token address from the factory
  const tokenAddress = await factory.getIPropertyToken(propertyId);
  const tokenBalanceBefore = await ethers.provider.getBalance(tokenAddress);
  const sellerBalanceBefore = await ethers.provider.getBalance(seller);

  console.log("🏦 PropertyToken balance before:", ethers.formatEther(tokenBalanceBefore), "ETH");
  console.log("💰 Seller balance before:", ethers.formatEther(sellerBalanceBefore), "ETH");

  // 🔄 Withdraw ETH
  console.log("🔄 Withdrawing ETH from PropertyToken...");
  const tx = await factory.withdrawETHFromToken(propertyId);
  const receipt = await tx.wait();

  console.log("✅ Withdraw successful!");
  console.log("📦 Transaction hash:", receipt.hash);

  // Recheck balances
  const tokenBalanceAfter = await ethers.provider.getBalance(tokenAddress);
  const sellerBalanceAfter = await ethers.provider.getBalance(seller);

  console.log("🏦 PropertyToken balance after:", ethers.formatEther(tokenBalanceAfter), "ETH");
  console.log("💰 Seller balance after:", ethers.formatEther(sellerBalanceAfter), "ETH");

  const delta = sellerBalanceAfter - sellerBalanceBefore;
  console.log("📈 ETH received by seller:", ethers.formatEther(delta), "ETH");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
