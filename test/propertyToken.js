const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PropertyTokenFactory", function () {
  let owner, seller, whimsy, buyer, other;
  let factory, tokenAddress, token;
  const initialSupply = 1000;

  beforeEach(async function () {
    [owner, seller, whimsy, buyer, other] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("PropertyTokenFactory");
    factory = await Factory.deploy(whimsy.address);
    await factory.waitForDeployment();

    const tx = await factory.createIPropertyToken(
      "Test Property",
      "TP",
      initialSupply,
      seller.address
    );

    const receipt = await tx.wait();
    const event = receipt.logs.find(log => log.fragment.name === "NewProperty");
    tokenAddress = event.args.tokenAddress;

    const Token = await ethers.getContractFactory("PropertyToken");
    token = await Token.attach(tokenAddress);
  });

  it("should create a new property token", async function () {
    expect(await token.name()).to.equal("Test Property");
    expect(await token.symbol()).to.equal("TP");
    expect(await token.balanceOf(seller.address)).to.equal(initialSupply * 97 / 100);
    expect(await token.balanceOf(whimsy.address)).to.equal(initialSupply * 3 / 100);
  });

  it("should set sale parameters", async function () {
    await factory.setSaleParameters(1, 670, ethers.parseEther("0.01"), 300);
    expect(await token.tokensForSale()).to.equal(670);
    expect(await token.tokenPrice()).to.equal(ethers.parseEther("0.01"));
    expect(await token.targetSellerOwnership()).to.equal(300);
  });

  it("should allow buyer to agree to disclaimer", async function () {
    await token.connect(buyer).agreeDisclaimer();
    expect(await token.hasAgreedDisclaimer(buyer.address)).to.equal(true);
  });

  it("should reserve tokens", async function () {
    await token.connect(buyer).agreeDisclaimer();
    await factory.setSaleParameters(1, 300, ethers.parseEther("0.01"), 300);
    const value = ethers.parseEther("3.0");
    await factory.connect(buyer).reserveTokens(1, 300, { value });
    const reservation = await token.pendingReservations(buyer.address);
    expect(reservation.amount).to.equal(300);
  });

  it("should buy tokens", async function () {
    await token.connect(buyer).agreeDisclaimer();
    await factory.setSaleParameters(1, 100, ethers.parseEther("0.01"), 300);
    const value = ethers.parseEther("1.0");
    await factory.connect(buyer).buyTokens(1, 100, { value });
    expect(await token.balanceOf(buyer.address)).to.equal(100);
  });

  it("should allow seller to update their address", async function () {
    await factory.connect(seller).updateSellerAddress(1, other.address);
    expect(await token.seller()).to.equal(other.address);
  });

  it("should create and finalize a proposal", async function () {
    await factory.createProposal(1, "Test Proposal");
    await token.connect(seller).vote(0, true);
    await factory.finalizeProposal(1, 0);
    const [desc, yes, no, finalized] = await token.getProposal(0);
    expect(finalized).to.equal(true);
    expect(desc).to.equal("Test Proposal");
  });

  it("should increase supply", async function () {
    await factory.increaseSupply(1, 500);
    expect(await token.totalSupply()).to.equal(initialSupply + 500);
  });
});
