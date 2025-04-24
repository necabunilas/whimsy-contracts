const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying from:", deployer.address);

  const Factory = await ethers.getContractFactory("PropertyTokenFactory");
  const factory = await Factory.deploy("0x278604Cf1CB4c1680278E3f6d541764F52358591", "0xCD2FB11F22FAE9c1c455C670e42F0Af5a5De391a"); // replace with valid address

  await factory.waitForDeployment();

  console.log("Factory deployed to:", await factory.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
