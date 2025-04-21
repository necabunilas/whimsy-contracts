const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying from:", deployer.address);

  const Factory = await ethers.getContractFactory("PropertyTokenFactory");
  const factory = await Factory.deploy(deployer.address); // replace with valid address

  await factory.waitForDeployment();

  console.log("Factory deployed to:", await factory.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
