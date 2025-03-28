require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 50 // or try 1 for smallest size
      }
    }
  },
  networks: {
    base: {
      url: "https://sepolia.base.org", // Base Sepolia RPC
      chainId: 84532,
      accounts: [process.env.PRIVATE_KEY]  // Load from .env
    }
  }
};