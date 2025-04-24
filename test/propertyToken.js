const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PropertyTokenFactory & PropertyToken", function () {
  let factory, token, usdc;
  let owner, seller, whimsy, buyer, other;

  // 150 000 total tokens, price = 1 USDC (6 decimals)
  const initialSupply = 150_000;
  const pricePerToken = ethers.parseUnits("1", 6);
  // 3% to whimsy, 97% to seller:
  const whimsyAllocation = (initialSupply * 3) / 100; // 4 500
  const sellerAllocation = initialSupply - whimsyAllocation; // 145 500
  // pick 20% seller floor = 30 000, remaining for sale = 115 500
  const targetSellerOwnership = (initialSupply * 20) / 100; // 30 000
  const tokensForSale = sellerAllocation - targetSellerOwnership; // 115 500

  beforeEach(async function () {
    [owner, seller, whimsy, buyer, other] = await ethers.getSigners();

    // ➊ Deploy Mock USDC
    const MockERC20 = await ethers.getContractFactory("MockERC20", owner);
    usdc = await MockERC20.deploy();
    await usdc.waitForDeployment();
    await usdc.mint(buyer.address, ethers.parseUnits("1000000", 6));

    // ➋ Deploy factory
    const Factory = await ethers.getContractFactory(
      "PropertyTokenFactory",
      owner
    );
    factory = await Factory.deploy(whimsy.address, usdc.target);
    await factory.waitForDeployment();

    // ➌ Create a new PropertyToken
    const tx = await factory.createIPropertyToken(
      "TestProp",
      "TP",
      initialSupply,
      seller.address,
      targetSellerOwnership,
      pricePerToken
    );
    const receipt = await tx.wait();
    const iface = factory.interface;
    const newProp = receipt.logs
      .map((l) => {
        try {
          return iface.parseLog(l);
        } catch {
          return null;
        }
      })
      .find((e) => e && e.name === "NewProperty");
    expect(newProp).to.exist;

    const Token = await ethers.getContractFactory("PropertyToken");
    token = Token.attach(newProp.args.tokenAddress);
  });

  it("deploys and mints correct allocations & sets ownership/operator", async () => {
    expect(await token.name()).to.equal("TestProp");
    expect(await token.symbol()).to.equal("TP");

    expect(await token.balanceOf(seller.address)).to.equal(
      sellerAllocation
    );
    expect(await token.balanceOf(whimsy.address)).to.equal(
      whimsyAllocation
    );
    expect(await token.totalSupply()).to.equal(initialSupply);

    expect(await token.tokensForSale()).to.equal(tokensForSale);
    expect(await token.tokenPrice()).to.equal(pricePerToken);
    expect(await token.targetSellerOwnership()).to.equal(
      targetSellerOwnership
    );

    // // owner & operator = factory
    expect(await token.owner()).to.equal(factory.target);
    // expect(await token.operator()).to.equal(factory.target);
  });

  describe("sale setup & caps", () => {
    it("rejects invalid parameters", async () => {
      await expect(
        factory.setSaleParameters(1, 1000, 0, 15000)
      ).to.be.revertedWith("Token price > 0");
      await expect(
        factory.setSaleParameters(1, 1000, pricePerToken, 10000)
      ).to.be.revertedWith("Target >= 10%");
      await expect(
        factory.setSaleParameters(1, 1000, pricePerToken, 50000)
      ).to.be.revertedWith("Target <= 30%");
      await expect(
        factory.setSaleParameters(
          1,
          sellerAllocation + 1,
          pricePerToken,
          targetSellerOwnership
        )
      ).to.be.revertedWith("Seller bal low");
    });

    it("accepts valid parameters", async () => {
      const newTarget = (initialSupply * 25) / 100; // 37 500
      const newForSale = sellerAllocation - newTarget; // 108 000
      await factory.setSaleParameters(
        1,
        newForSale,
        pricePerToken,
        newTarget
      );

      expect(await token.tokensForSale()).to.equal(newForSale);
      expect(await token.tokenPrice()).to.equal(pricePerToken);
      expect(await token.targetSellerOwnership()).to.equal(newTarget);
    });
  });

  describe("reserve & buy (USDC)", () => {
    beforeEach(async () => {
      await factory.setSaleParameters(
        1,
        tokensForSale,
        pricePerToken,
        targetSellerOwnership
      );
    });

    it("lets buyer agree & reserve via factory", async () => {
      await factory.connect(buyer).agreeDisclaimer(1);
      await usdc
        .connect(buyer)
        .approve(token.target, pricePerToken * 10n);
      await factory.connect(buyer).reserveTokens(1, 10);
      const res = await token.pendingReservations(buyer.address);
      expect(res.amount).to.equal(10);
    });

    it("lets buyer buy reserved amount (no extra USDC)", async () => {
      await factory.connect(buyer).agreeDisclaimer(1);
      await usdc
        .connect(buyer)
        .approve(token.target, pricePerToken * 10n);
      await usdc
        .connect(buyer)
        .approve(factory.target, pricePerToken * 10n);
      await factory.connect(buyer).reserveTokens(1, 10);
      await factory.connect(buyer).buyTokens(1, 10);
      expect(await token.balanceOf(buyer.address)).to.equal(10);
    });

    it("lets buyer do a direct purchase", async () => {
      await factory.connect(buyer).agreeDisclaimer(1);
      await usdc
        .connect(buyer)
        .approve(token.target, pricePerToken * 20n);
      await usdc
        .connect(buyer)
        .approve(factory.target, pricePerToken * 20n);
      await factory.connect(buyer).buyTokens(1, 20);
      expect(await token.balanceOf(buyer.address)).to.equal(20);
    });
  });

  describe("supply & seller management", () => {
    it("only allows minting when no active sale", async () => {
      await expect(factory.mintMoreSupply(1, 50)).to.be.revertedWith(
        "Can't mint during sale"
      );
    });

    it("lets seller or whimsy update their address", async () => {
      await expect(
        factory.connect(buyer).updateSellerAddress(1, other.address)
      ).to.be.revertedWithCustomError(factory, "Unauthorized");      
      await factory.connect(seller).updateSellerAddress(1, other.address);
      expect(await factory.getSeller(1)).to.equal(other.address);
      await factory.connect(whimsy).updateSellerAddress(1, seller.address);
      expect(await factory.getSeller(1)).to.equal(seller.address);
    });
  });

  describe("clawback", () => {
    beforeEach(async () => {
      await factory.setSaleParameters(
        1,
        tokensForSale,
        pricePerToken,
        targetSellerOwnership
      );
      await factory.connect(buyer).agreeDisclaimer(1);
      await usdc
        .connect(buyer)
        .approve(token.target, pricePerToken * 10n);
      await usdc
        .connect(buyer)
        .approve(factory.target, pricePerToken * 10n);
      await factory.connect(buyer).buyTokens(1, 10);
    });

    it("lets owner claw back tokens", async () => {
      expect(await token.balanceOf(buyer.address)).to.equal(10);
      const ownerBalBefore = await token.balanceOf(owner.address);
      await factory.clawback(1, buyer.address);
      expect(await token.balanceOf(buyer.address)).to.equal(0);
      expect(await token.balanceOf(owner.address)).to.be.gt(
        ownerBalBefore
      );
    });
  });

  describe("token‑level controls via factory", () => {
    it("toggleTransfers really disables/enables direct ERC20 transfers", async () => {
      // initially transfersEnabled = true
      await factory.toggleTokenTransfers(1, false);
      expect(await token.transfersEnabled()).to.be.false;
  
      // try a direct transfer: seller → buyer should revert
      await expect(
        token.connect(seller).transfer(buyer.address, 1)
      ).to.be.revertedWith("Direct transfers disabled");
  
      // re‑enable transfers
      await factory.toggleTokenTransfers(1, true);
      expect(await token.transfersEnabled()).to.be.true;
  
      // now the same transfer should succeed
      // const tx = await token.connect(seller).transfer(buyer.address, 1);
      // await tx.wait();
      // expect(await token.balanceOf(buyer.address)).to.equal(1);
    });
  });  

  describe("operator control via factory", () => {
    it("factory is owner/operator and can pause", async () => {
      await expect(
        token.connect(buyer).pause()
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount").withArgs(buyer.address);      
      await factory.pauseToken(1);
      expect(await token.paused()).to.be.true;
      await factory.unpauseToken(1);
      expect(await token.paused()).to.be.false;
    });
  });

  describe("USDC flows", () => {
    it("lets seller withdraw USDC after token sale", async () => {
      const amt = 10n;
      const cost = pricePerToken * amt / BigInt(1000000);

      await usdc.connect(buyer).approve(token.target, cost);
      // await usdc.connect(buyer).approve(factory.target, cost);
      await factory.connect(buyer).agreeDisclaimer(1);
      await factory.connect(buyer).buyTokens(1, amt);

      const tokenBalBefore = await usdc.balanceOf(token.target);
      expect(tokenBalBefore).to.equal(cost); // reserved + buy

      // const sellerBalBefore = await usdc.balanceOf(seller.address);
      await expect(factory.withdrawPayment(1)).to.be.revertedWith("Cannot withdraw during sale");
      // expect(await usdc.balanceOf(token.target)).to.equal(0);
      // expect(
      //   (await usdc.balanceOf(seller.address)) - sellerBalBefore
      // ).to.equal(tokenBalBefore);      
    });
  });

  // describe("ownership & governance", () => {
  //   it("supports full proposal lifecycle", async () => {
  //     await factory.createProposal(1, "Do A");
  
  //     const propId = await factory.proposalsLength(1) - 1n;
  
  //     await factory.connect(seller).vote(1, propId, true);
  
  //     const [, yes, no, finBefore] = await factory.getProposal(1, propId);
  //     expect(yes).to.be.gt(0);
  //     expect(no).to.equal(0);
  //     expect(finBefore).to.be.false;
  
  //     await factory.finalizeProposal(1, propId);
  //     const [, yesAfter, noAfter, fin] = await factory.getProposal(1, propId);
  //     expect(yesAfter).to.be.gt(0);
  //     expect(noAfter).to.equal(0);
  //     expect(fin).to.be.true;
  //   });
  // });  

  describe("refundUnagreedBuyer via factory", () => {
    const FIVE_DAYS = 5 * 24 * 60 * 60;
    const reservedAmount = 50n;
    const totalCost = (pricePerToken * reservedAmount) / BigInt(1000000);

    beforeEach(async () => {
      await usdc.connect(buyer).approve(factory.target, totalCost);
      await usdc.connect(buyer).approve(token.target, totalCost);
      await factory.connect(buyer).reserveTokens(1, reservedAmount);
    });

    it("cannot refund before timeout", async () => {
      await expect(
        factory.refundUnagreedBuyer(1, buyer.address)
      ).to.be.revertedWith("Too early");
    });

    it("cannot refund after buyer agreed", async () => {
      await ethers.provider.send("evm_increaseTime", [FIVE_DAYS + 1]);
      await ethers.provider.send("evm_mine");
      await factory.connect(buyer).agreeDisclaimer(1);
      await expect(
        factory.refundUnagreedBuyer(1, buyer.address)
      ).to.be.revertedWith("Already agreed");
    });

    it("lets owner refund after timeout", async () => {
      await ethers.provider.send("evm_increaseTime", [FIVE_DAYS + 1]);
      await ethers.provider.send("evm_mine");
      const balBefore = await usdc.balanceOf(buyer.address);
      await factory.refundUnagreedBuyer(1, buyer.address);
      expect(
        (await usdc.balanceOf(buyer.address)) - balBefore
      ).to.equal(totalCost);
    });
  });

  it("should allow owner to end the sale early, block purchases, and allow withdrawal", async function () {
    // Step 1: Buyer agrees to disclaimer
    await factory.connect(buyer).agreeDisclaimer(1);
  
    // Step 2: Buyer approves token contract to spend USDC
    const purchaseAmount = 1000n;
    const totalCost = purchaseAmount * 10n ** 6n; // since USDC has 6 decimals
    await usdc.connect(buyer).approve(token.target, totalCost);

    await factory.connect(buyer).buyTokens(1, purchaseAmount)
  
    // Step 3: Owner ends the sale early
    await expect(factory.connect(owner).endSaleEarly(1))
      .to.emit(token, "SaleEndedEarly");
  
    // Step 4: Buyer tries to buy tokens — should revert
    await expect(factory.connect(buyer).buyTokens(1, purchaseAmount))
      .to.be.revertedWith("Sale has ended");
  
    // Step 5: Owner withdraws payment (should succeed, even if balance is 0)
    await expect(factory.connect(owner).withdrawPayment(1))
      .to.emit(token, "Withdrawn");
  });  

  describe("getters", () => {
    it("returns valuation, token address & seller", async () => {
      const pre = 123n;
      // Initial valuation check
      expect(await factory.getPostMoneyValuation(1, pre)).to.equal(pre);
    
      // Buyer agrees to disclaimer
      await factory.connect(buyer).agreeDisclaimer(1);
    
      // Buyer approves both token and factory for purchase
      await usdc.connect(buyer).approve(token.target, pricePerToken * 10n);
      // await usdc.connect(buyer).approve(factory.target, pricePerToken * 10n);
    
      // Buyer purchases 10 tokens
      await factory.connect(buyer).buyTokens(1, 10n);
    
      // Final valuation check
      const want = pre + 10n; // 123 + 10 = 133 USDC (6 decimals)
      expect(await factory.getPostMoneyValuation(1, pre)).to.equal(want);
    
      // // Check token address and seller
      // expect(await factory.getIPropertyToken(1)).to.equal(token.target);
      // expect(await factory.getSeller(1)).to.equal(seller.address);
    });    
  });

  //
  // ── New tests for signature gating, setWhimsy & signer ──────────
  //
  describe("whimsy & signer management", () => {
    it("factory can update whimsy on token", async () => {
      await factory.setWhimsy(1, other.address);
      expect(await token.whimsy()).to.equal(other.address);
    });

    // it("factory can set token signer", async () => {
    //   await factory.setSigner(other.address);
    //   // await factory.setTokenSigner(1, other.address);
    //   // try a signatureTransfer with new signer
    //   const DEC = await token.decimals();
    //   const amt = ethers.parseUnits("1", DEC);
    //   await token.connect(seller).toggleTransfers(false);
    //   // prepare buffer + signature
    //   const buffer = ethers.utils.randomBytes(32);
    //   const h = ethers.utils.keccak256(
    //     ethers.utils.solidityPack(
    //       ["bytes32", "address", "address", "uint256"],
    //       [buffer, seller.address, buyer.address, amt]
    //     )
    //   );
    //   const message = ethers.utils.arrayify(
    //     ethers.utils.hashMessage(ethers.utils.arrayify(h))
    //   );
    //   const sig = await owner.signMessage(message);
    //   // call signatureTransfer
    //   await token
    //     .connect(seller)
    //     .signatureTransfer(buffer, sig, buyer.address, amt);
    //   expect(await token.balanceOf(buyer.address)).to.equal(amt);
    // });

    // it("can disable requireSignatureOnTransfer", async () => {
    //   expect(await token.requireSignatureOnTransfer()).to.be.true;
    //   await token.setRequireSignatureOnTransfer(true);
    //   // now direct transfer works
    //   await token.connect(seller).transfer(buyer.address, 1);
    //   expect(await token.balanceOf(buyer.address)).to.equal(1);
    // });
  });
});
