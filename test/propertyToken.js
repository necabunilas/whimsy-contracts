const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PropertyTokenFactory", function () {
  let factory, token, owner, seller, whimsy, buyer, other;

  beforeEach(async function () {
    [owner, seller, whimsy, buyer, other] = await ethers.getSigners();
    const initialSupply = 1000;

    // Deploy the factory contract.
    const Factory = await ethers.getContractFactory(
      "PropertyTokenFactory",
      owner
    );
    factory = await Factory.deploy(whimsy.address);
    await factory.waitForDeployment();

    // Create a new property token.
    const tx = await factory.createIPropertyToken(
      "TestProp",
      "TP",
      initialSupply,
      seller.address
    );
    const receipt = await tx.wait();

    // Parse the NewProperty event.
    const event = receipt.logs
      .map((log) => {
        try {
          return factory.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find((parsed) => parsed && parsed.name === "NewProperty");

    expect(event).to.not.be.undefined;
    const tokenAddress = event.args.tokenAddress;

    // Attach the token contract.
    const PropertyToken = await ethers.getContractFactory("PropertyToken");
    token = PropertyToken.attach(tokenAddress);
  });

  it("should create a new property token", async function () {
    expect(await token.name()).to.equal("TestProp");
    expect(await token.symbol()).to.equal("TP");
  });

  it("should set sale parameters", async function () {
    await factory.setSaleParameters(1, 670, ethers.parseEther("0.01"), 300);
    expect(await token.tokensForSale()).to.equal(670);
    expect(await token.tokenPrice()).to.equal(ethers.parseEther("0.01"));
    expect(await token.targetSellerOwnership()).to.equal(300);
  });

  it("should allow buyer to agree to disclaimer", async function () {
    const tokenAddr = await factory.getIPropertyToken(1);
    const tokenInstance = await ethers.getContractAt(
      "PropertyToken",
      tokenAddr
    );
    await tokenInstance.connect(buyer).agreeDisclaimer();
    expect(await tokenInstance.hasAgreedDisclaimer(buyer.address)).to.equal(
      true
    );
  });

  it("should reserve tokens", async function () {
    await token.connect(buyer).agreeDisclaimer();

    const tokenPrice = ethers.parseEther("0.01");
    const tokensForSale = 670;
    const targetOwnership = 300;

    await factory.setSaleParameters(
      1,
      tokensForSale,
      tokenPrice,
      targetOwnership
    );
    const value = tokenPrice * BigInt(tokensForSale);
    await token.connect(buyer).reserveTokens(tokensForSale, { value });

    const reservation = await token.pendingReservations(buyer.address);
    expect(reservation.amount).to.equal(tokensForSale);
  });

  it("should buy tokens", async function () {
    const tokenAddress = await factory.getIPropertyToken(1);
    const tokenInstance = await ethers.getContractAt(
      "PropertyToken",
      tokenAddress
    );

    // Buyer agrees to disclaimer directly on the token contract.
    await tokenInstance.connect(buyer).agreeDisclaimer();

    const buyAmount = 100;
    const tokenPrice = ethers.parseEther("0.01");
    const tokensForSale = 670;
    const targetOwnership = 300;

    // Set sale parameters via the factory.
    await factory.setSaleParameters(
      1,
      tokensForSale,
      tokenPrice,
      targetOwnership
    );
    expect(await tokenInstance.tokensForSale()).to.equal(tokensForSale);

    const value = tokenPrice * BigInt(buyAmount);
    // Buyer calls buyTokens directly so that msg.sender is buyer.
    await tokenInstance.connect(buyer).buyTokens(buyAmount, { value });

    const buyerBalance = await tokenInstance.balanceOf(buyer.address);
    expect(buyerBalance).to.equal(buyAmount);
  });

  it("should not allow buying tokens without agreeing to disclaimer", async function () {
    const tokenAddress = await factory.getIPropertyToken(1);
    const tokenInstance = await ethers.getContractAt(
      "PropertyToken",
      tokenAddress
    );

    const buyAmount = 50;
    const tokenPrice = ethers.parseEther("0.01");
    const tokensForSale = 670;
    const targetOwnership = 300;

    await factory.setSaleParameters(
      1,
      tokensForSale,
      tokenPrice,
      targetOwnership
    );
    const value = tokenPrice * BigInt(buyAmount);

    // Attempting to buy tokens without disclaimer should revert.
    await expect(
      tokenInstance.connect(buyer).buyTokens(buyAmount, { value })
    ).to.be.revertedWith("Must agree to disclaimer first");
  });

  it("should not allow reserving tokens with incorrect ETH sent", async function () {
    await token.connect(buyer).agreeDisclaimer();

    const tokenPrice = ethers.parseEther("0.01");
    const tokensForSale = 670;
    await factory.setSaleParameters(1, tokensForSale, tokenPrice, 300);

    // Sending less ETH than required.
    const wrongValue = tokenPrice * BigInt(100) - BigInt(1);
    await expect(
      token.connect(buyer).reserveTokens(100, { value: wrongValue })
    ).to.be.revertedWith("Incorrect ETH sent");
  });

  it("should allow seller to update their address", async function () {
    await factory.connect(seller).updateSellerAddress(1, other.address);
    expect(await token.seller()).to.equal(other.address);
  });

  it("should not allow non-seller to update seller address", async function () {
    await expect(factory.connect(buyer).updateSellerAddress(1, other.address))
      .to.be.reverted;
  });

  it("should create and finalize a proposal", async function () {
    await factory.createProposal(1, "Test Proposal");
    await token.connect(seller).vote(0, true);
    await factory.finalizeProposal(1, 0);
    const [desc, , , finalized] = await token.getProposal(0);
    expect(finalized).to.equal(true);
    expect(desc).to.equal("Test Proposal");
  });

  it("should not allow a vote with no voting power", async function () {
    await factory.createProposal(1, "No Token Holder Proposal");
    await expect(token.connect(buyer).vote(0, true)).to.be.revertedWith(
      "No voting power"
    );
  });

  it("should not allow double voting", async function () {
    await factory.createProposal(1, "Double Voting Proposal");
    await token.connect(seller).vote(0, true);
    await expect(token.connect(seller).vote(0, false)).to.be.revertedWith(
      "Already voted"
    );
  });

  it("should increase supply", async function () {
    await factory.increaseSupply(1, 500);
    expect(await token.totalSupply()).to.equal(1500);
  });

  it("should refund unagreed buyer after timeout", async function () {
    // Buyer reserves tokens without agreeing to disclaimer.
    const tokensToReserve = 50;
    const tokenPrice = ethers.parseEther("0.01");
    const tokensForSale = 670;
    await factory.setSaleParameters(1, tokensForSale, tokenPrice, 300);
    const value = tokenPrice * BigInt(tokensToReserve);

    await token.connect(buyer).reserveTokens(tokensToReserve, { value });

    // Increase time by more than the AGREEMENT_TIMEOUT (5 days).
    await ethers.provider.send("evm_increaseTime", [5 * 24 * 60 * 60 + 1]);
    await ethers.provider.send("evm_mine");

    // Capture buyer's balance before the refund.
    const buyerBalanceBefore = await ethers.provider.getBalance(buyer.address);

    // Refund unagreed buyer via the factory function.
    await factory.refundUnagreedBuyer(1, buyer.address);

    // The reservation should be cleared.
    const reservation = await token.pendingReservations(buyer.address);
    expect(reservation.amount).to.equal(0);

    // tokensForSale should remain unchanged (670).
    expect(await token.tokensForSale()).to.equal(tokensForSale);

    // Optionally, check that buyer received ETH back (allowing for gas costs).
    const buyerBalanceAfter = await ethers.provider.getBalance(buyer.address);
    expect(buyerBalanceAfter).to.be.gt(buyerBalanceBefore);
  });

  it("should not refund unagreed buyer before timeout", async function () {
    const tokensToReserve = 50;
    const tokenPrice = ethers.parseEther("0.01");
    const tokensForSale = 670;
    await factory.setSaleParameters(1, tokensForSale, tokenPrice, 300);
    const value = tokenPrice * BigInt(tokensToReserve);

    await token.connect(buyer).reserveTokens(tokensToReserve, { value });

    await expect(
      factory.refundUnagreedBuyer(1, buyer.address)
    ).to.be.revertedWith("Timeout not reached");
  });

  it("should not allow seller to transfer tokens below target seller ownership", async function () {
    await factory.setSaleParameters(1, 670, ethers.parseEther("0.01"), 300);
    await expect(
      token.connect(seller).transfer(buyer.address, 671)
    ).to.be.revertedWith("Seller must retain minimum ownership");
  });

  it("should not allow transferring tokens that exceed the 15% buyer cap", async function () {
    await token.connect(seller).transfer(buyer.address, 150);
    await expect(
      token.connect(seller).transfer(buyer.address, 1)
    ).to.be.revertedWith("Recipient exceeds 15% cap");
  });

  it("should allow owner to withdraw ETH", async function () {
    // Get the token address from the factory mapping.
    const tokenAddr = await factory.getIPropertyToken(1);
    console.log("Token address:", tokenAddr);

    // Check that the token contract is deployed (has code)
    const tokenCode = await ethers.provider.getCode(tokenAddr);
    console.log("Token code:", tokenCode);
    expect(tokenCode).to.not.equal("0x");

    // Deposit 1 ETH into the token contract.
    const deposit = ethers.parseEther("1");
    console.log("Depositing 1 ETH to token contract...");
    const depositTx = await owner.sendTransaction({
      to: tokenAddr,
      value: deposit,
    });
    await depositTx.wait();

    const tokenBalanceAfterDeposit = await ethers.provider.getBalance(
      tokenAddr
    );
    console.log(
      "Token contract balance after deposit:",
      tokenBalanceAfterDeposit.toString()
    );
    expect(tokenBalanceAfterDeposit).to.equal(deposit);

    // Get seller's balance before withdrawal.
    const sellerBalanceBefore = await ethers.provider.getBalance(
      seller.address
    );
    console.log(
      "Seller balance before withdrawal:",
      sellerBalanceBefore.toString()
    );

    // Withdraw ETH via the factory's withdraw function using the owner signer.
    console.log("Calling factory.withdraw(1)...");
    const withdrawTx = await factory.connect(owner).withdraw(1);
    const receipt = await withdrawTx.wait();
    console.log("Withdraw tx receipt events:", receipt.events);

    // Get seller's balance after withdrawal.
    const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
    console.log(
      "Seller balance after withdrawal:",
      sellerBalanceAfter.toString()
    );

    // Check that the seller's balance increased.
    expect(sellerBalanceAfter).to.be.gt(sellerBalanceBefore);
  });

  it("should not allow non-operator to finalize a proposal", async function () {
    await factory.createProposal(1, "Unauthorized Finalize Proposal");
    await token.connect(seller).vote(0, true);
    await expect(token.connect(buyer).finalizeProposal(0)).to.be.revertedWith(
      "Not authorized: operator only"
    );
  });
});
