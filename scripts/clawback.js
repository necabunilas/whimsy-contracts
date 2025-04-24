// scripts/clawback.js
require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  // ── CONFIG ─────────────────────────────────────────────
  const FACTORY_ADDR = "0x9266F18FD4B8542eeAe5Cc9b019E5356bABab05d";
  const PROPERTY_ID  = 1;
  const TARGET_OWNER = "0x278604Cf1CB4c1680278E3f6d541764F52358591";

  // ── SETUP SIGNER & FACTORY ─────────────────────────────
  const [claimer] = await ethers.getSigners();  // must be factory.owner()
  console.log("🔐 Claimer:", claimer.address);

  const factory = await ethers.getContractAt(
    "PropertyTokenFactory",
    FACTORY_ADDR,
    claimer
  );

  // ── LOOK UP THE PROPERTY TOKEN ──────────────────────────
  const tokenAddr = await factory.getIPropertyToken(PROPERTY_ID);
  console.log("🏠 PropertyToken @", tokenAddr);

  // ── ATTACH ERC20 ABI ───────────────────────────────────
  const token = await ethers.getContractAt(
    // the PropertyToken implements ERC20 + decimals()
    ["function balanceOf(address) view returns(uint256)",
     "function decimals() view returns(uint8)"],
    tokenAddr,
    ethers.provider
  );

  const DEC = await token.decimals();

  // ── CHECK BALANCE BEFORE ─────────────────────────────────
  const balBefore = await token.balanceOf(TARGET_OWNER);
  console.log(
    `📊 ${TARGET_OWNER} balance before:`,
    ethers.formatUnits(balBefore, DEC),
    "tokens"
  );

  if (balBefore == 0) {
    console.log("⚠️ nothing to claw back, exiting.");
    return;
  }

  // ── CALL CLAWBACK ───────────────────────────────────────
  console.log("🚨 submitting clawback...");
  try {
    const tx = await factory.clawback(PROPERTY_ID, TARGET_OWNER, {
      gasLimit: 200_000
    });
    const receipt = await tx.wait();
    console.log("✅ Clawback tx hash:", receipt.transactionHash);
  } catch (err) {
    console.error("❌ Clawback failed:", err);
    process.exit(1);
  }

  // ── CHECK BALANCE AFTER ──────────────────────────────────
  const balAfter    = await token.balanceOf(TARGET_OWNER);
  const ownerNewBal = await token.balanceOf(claimer.address);

  console.log(
    `📉 ${TARGET_OWNER} balance after:`,
    ethers.formatUnits(balAfter, DEC),
    "tokens"
  );
  console.log(
    `🏦 Claimer (factory.owner) balance:`,
    ethers.formatUnits(ownerNewBal, DEC),
    "tokens"
  );
}

main().catch((err) => {
  console.error("❌ error in clawback script:", err);
  process.exit(1);
});
