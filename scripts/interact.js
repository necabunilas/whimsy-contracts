const { ethers } = require("hardhat");

async function main() {
  const factoryAddress = "0xf08313e987f5AB12A629cD6bce7300fdF593F239"; // 🔁 replace this
  const whimsy = "0xA845cc8A1DF843a2D872A7D9F27eC330a068fcb8";              // 🔁 replace this
  const seller = "0xA845cc8A1DF843a2D872A7D9F27eC330a068fcb8";              // 🔁 replace this
  const initialSupply = 1000;

  const [caller] = await ethers.getSigners();
  console.log("Using account:", caller.address);

  const Factory = await ethers.getContractFactory("PropertyTokenFactory");
  const factory = Factory.attach(factoryAddress);

  // Create a token
  const tx = await factory.createIPropertyToken(
    "Sample Property",
    "SPT",
    initialSupply,
    seller
  );
  const receipt = await tx.wait();

  // Parse the event for the token address
  const iface = factory.interface;
  const event = receipt.logs
    .map((log) => {
      try {
        return iface.parseLog(log);
      } catch {
        return null;
      }
    })
    .find((e) => e && e.name === "NewProperty");

  if (event) {
    const tokenAddress = event.args.tokenAddress;
    console.log("✅ PropertyToken deployed at:", tokenAddress);
  } else {
    console.log("⚠️ NewProperty event not found.");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
