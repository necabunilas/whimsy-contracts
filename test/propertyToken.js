const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PropertyTokenFactory & PropertyToken", function () {
  let factory, token;
  let owner, seller, whimsy, buyer, other;
  const initialSupply = 1000;
  // at the top of your test file
  const parseEther = ethers.utils?.parseEther ?? ethers.parseEther;

  beforeEach(async function () {
    [owner, seller, whimsy, buyer, other] = await ethers.getSigners();

    // 1) Deploy factory
    const Factory = await ethers.getContractFactory(
      "PropertyTokenFactory",
      owner
    );
    factory = await Factory.deploy(whimsy.address);
    await factory.waitForDeployment();

    // 2) Create a new token via the factory
    const tx = await factory.createIPropertyToken(
      "TestProp",
      "TP",
      initialSupply,
      seller.address
    );
    const receipt = await tx.wait();

    // 3) Find and parse the NewProperty event in receipt.logs
    const iface = factory.interface;
    const newProp = receipt.logs
      .map((log) => {
        try {
          return iface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find((parsed) => parsed && parsed.name === "NewProperty");

    expect(newProp, "must emit NewProperty").to.exist;
    const tokenAddress = newProp.args.tokenAddress;

    // 4) Attach the PropertyToken
    const Token = await ethers.getContractFactory("PropertyToken");
    token = Token.attach(tokenAddress);
  });

  it("deploys and mints correct allocations & sets ownership/operator", async () => {
    // Metadata
    expect(await token.name()).to.equal("TestProp");
    expect(await token.symbol()).to.equal("TP");

    // Minted: 97% → seller, 3% → whimsy
    expect(await token.balanceOf(seller.address)).to.equal(
      (initialSupply * 97) / 100
    );
    expect(await token.balanceOf(whimsy.address)).to.equal(
      (initialSupply * 3) / 100
    );
    expect(await token.totalSupply()).to.equal(initialSupply);

    // Owner & operator should both be the factory
    expect(await token.owner()).to.equal(factory.target);
    expect(await token.operator()).to.equal(factory.target);
  });

  describe("sale setup & caps", () => {
    it("rejects invalid parameters", async () => {
      // price zero
      await expect(
        factory.setSaleParameters(1, 100, 0, 100)
      ).to.be.revertedWith("Token price must be > 0");

      // target < 10%
      await expect(factory.setSaleParameters(1, 100, 1, 50)).to.be.revertedWith(
        "Target >= 10%"
      );

      // target > 30%
      await expect(
        factory.setSaleParameters(1, 100, 1, 400)
      ).to.be.revertedWith("Target <= 30%");

      // // tokensForSale > seller balance (97% of 1000 = 970)
      // // choose a target in-range (e.g. 200) so it hits the seller‑balance check
      await expect(
        factory.setSaleParameters(1, 980, 1, 200)
      ).to.be.revertedWith("Seller balance low");
    });

    it("accepts valid parameters", async () => {
      await factory.setSaleParameters(1, 670, 1, 300);
      const forSale = await token.tokensForSale();
      // read state from token
      expect(await token.tokensForSale()).to.equal(670);
      expect(await token.tokenPrice()).to.equal(1);
      expect(await token.targetSellerOwnership()).to.equal(300);
    });
  });

  describe("reserve & buy", () => {
    beforeEach(async () => {
      // open a sale: 700 for sale, price=1, seller keeps 300
      await factory.setSaleParameters(1, 670, 1, 300);
    });

    it("lets buyer agree & reserve via factory", async () => {
      await factory.connect(buyer).agreeDisclaimer(1);
      await factory.connect(buyer).reserveTokens(1, 10, { value: 10 });
      const res = await token.pendingReservations(buyer.address);
      console.log("response: ", res);
      expect(res.amount).to.equal(10);
    });

    it("lets buyer buy a reserved amount (no extra ETH)", async () => {
      await factory.connect(buyer).agreeDisclaimer(1);
      await factory.connect(buyer).reserveTokens(1, 10, { value: 10 });
      await factory.connect(buyer).buyTokens(1, 10, { value: 0 });
      expect(await token.balanceOf(buyer.address)).to.equal(10);
    });

    it("lets buyer do a direct purchase", async () => {
      await factory.connect(buyer).agreeDisclaimer(1);
      await factory.connect(buyer).buyTokens(1, 20, { value: 20 });
      expect(await token.balanceOf(buyer.address)).to.equal(20);
    });
  });

  describe("supply & seller management", () => {
    it("only allows minting when no active sale", async () => {
      await factory.mintMoreSupply(1, 50);
      expect(await token.totalSupply()).to.equal(initialSupply + 50);

      await factory.setSaleParameters(1, 705, 1, 315); // 900 = 1000 - 100
      await expect(factory.mintMoreSupply(1, 50)).to.be.revertedWith(
        "Can't mint during active sale"
      );
    });

    it("lets seller or whimsy update their address", async () => {
      // buyer cannot
      await expect(
        factory.connect(buyer).updateSellerAddress(1, other.address)
      ).to.be.revertedWithCustomError(factory, "Unauthorized");

      // seller can
      await factory.connect(seller).updateSellerAddress(1, other.address);
      expect(await factory.getSeller(1)).to.equal(other.address);

      // whimsy can reset
      await factory.connect(whimsy).updateSellerAddress(1, seller.address);
      expect(await factory.getSeller(1)).to.equal(seller.address);
    });
  });

  describe("clawback", () => {
    beforeEach(async () => {
      await factory.setSaleParameters(1, 670, 1, 300);
      const buyerBalBefore = await token.balanceOf(buyer.address);
      console.log("🔍 buyer balance before buying:", buyerBalBefore.toString());
      await factory.connect(buyer).agreeDisclaimer(1);
      await factory.connect(buyer).buyTokens(1, 10, { value: 10 });
      const buyerBalAfter = await token.balanceOf(buyer.address);
      console.log("🔍 buyer balance after buying:", buyerBalAfter.toString());
    });

    it("lets owner claw back tokens", async () => {
      // log balances before
      const buyerBalBefore = await token.balanceOf(buyer.address);
      const ownerBalBefore = await token.balanceOf(owner.address);
      console.log(
        "🔍 buyer balance before clawback:",
        buyerBalBefore.toString()
      );
      console.log(
        "🔍 owner balance before clawback:",
        ownerBalBefore.toString()
      );

      expect(buyerBalBefore).to.equal(10);

      // perform clawback
      await factory.clawback(1, buyer.address);

      // log balances after
      const buyerBalAfter = await token.balanceOf(buyer.address);
      const ownerBalAfter = await token.balanceOf(owner.address);
      console.log("🔍 buyer balance after clawback:", buyerBalAfter.toString());
      console.log("🔍 owner balance after clawback:", ownerBalAfter.toString());

      expect(buyerBalAfter).to.equal(0);
      expect(ownerBalAfter).to.be.greaterThan(ownerBalBefore);
    });
  });

  describe("token‑level controls via factory", () => {
    it("toggleTransfers really disables/enables direct ERC20 transfers", async () => {
      // initially transfersEnabled = true
      // disable transfers
      await factory.toggleTokenTransfers(1, false);
      expect(await token.transfersEnabled()).to.be.false;

      // try a direct transfer: seller → buyer should revert
      await expect(
        token.connect(seller).transfer(buyer.address, 1)
      ).to.be.revertedWith("Transfers are disabled");

      // re‑enable transfers
      await factory.toggleTokenTransfers(1, true);
      expect(await token.transfersEnabled()).to.be.true;

      // now the same transfer should succeed
      await token.connect(seller).transfer(buyer.address, 1);
      expect(await token.balanceOf(buyer.address)).to.equal(1);
    });
  });

  describe("operator control via factory", () => {
    it("only owner(factory) can setOperator, and updates operator", async () => {
      // buyer (not owner) should fail
      await expect(token.connect(buyer).pause()).to.be.revertedWithCustomError(
        token,
        "OwnableUnauthorizedAccount"
      );

      // factory (the owner) succeeds
      await factory.setTokenOperator(1, other.address);
      expect(await token.operator()).to.equal(other.address);

      // and we emit the event too:
      await expect(factory.setTokenOperator(1, buyer.address))
        .to.emit(token, "OperatorUpdated")
        .withArgs(other.address, buyer.address);
    });
  });

  // ETH flows
  describe("ETH flows", () => {
    it("lets factory withdraw any ETH held by token", async () => {
      // 1 ETH → token contract
      await owner.sendTransaction({
        to: token.target, // <— this must be present
        value: parseEther("1"), // <— and this too
      });

      const before = await ethers.provider.getBalance(seller.address);
      await factory.withdrawETHFromToken(1);
      const after = await ethers.provider.getBalance(seller.address);

      expect(after).to.be.gt(before);
    });
  });

  describe("ownership & governance", () => {
    it("supports full proposal lifecycle", async () => {
      // create
      await factory.createProposal(1, "Do A");
      const length = await token.proposalsLength();
      const propId = length - 1n; // subtract 1
  
      // log seller's balance before voting
      const sellerBal = await token.balanceOf(seller.address);
      console.log("🔍 seller balance (voting power):", sellerBal.toString());
  
      // vote (must use a stakeholder)
      await factory.connect(seller).vote(1, propId, true);
  
      // read yes/no tallies
      const [ , yes, no, finBefore ] = await token.getProposal(propId);
      console.log("🔍 yesVotes after vote:", yes.toString());
      console.log("🔍 noVotes after vote:", no.toString());
  
      // finalize
      await factory.finalizeProposal(1, propId);
      const [desc, yesAfter, noAfter, fin] = await token.getProposal(propId);
  
      console.log("🔍 finalized?:", fin);
  
      expect(desc).to.equal("Do A");
      expect(yesAfter).to.be.gt(0);
      expect(noAfter).to.equal(0);
      expect(fin).to.be.true;
    });
  });

  describe("refundUnagreedBuyer via factory", () => {
    const ONE_DAY = 24 * 60 * 60;
    const FIVE_DAYS = 5 * ONE_DAY;
  
    beforeEach(async () => {
      // open a sale: 500 for sale at price=1, seller keeps 500
      await factory.setSaleParameters(1, 670, 1, 300);
  
      // buyer agrees disclaimer *not* yet, we want them unagreed
      // reserve 50 tokens
      await factory.connect(buyer).reserveTokens(1, 50, { value: 50 });
    });
  
    it("cannot refund before timeout", async () => {
      // immediately calling should revert
      await expect(
        factory.refundUnagreedBuyer(1, buyer.address)
      ).to.be.revertedWith("Timeout not reached");
    });
  
    it("cannot refund after buyer has agreed", async () => {
      // fast‑forward past timeout
      await ethers.provider.send("evm_increaseTime", [FIVE_DAYS + 1]);
      await ethers.provider.send("evm_mine");
      // buyer now agrees disclaimer
      await factory.connect(buyer).agreeDisclaimer(1);
      await expect(
        factory.refundUnagreedBuyer(1, buyer.address)
      ).to.be.revertedWith("Buyer already agreed");
    });
  
    it("lets owner refund after timeout and clears reservation", async () => {
      // log reservation & totalReserved before timeout
      const resBefore = await token.pendingReservations(buyer.address);
      console.log("🔍 reservation before refund:", resBefore.amount.toString());
      const totalResBefore = await token.totalReserved();
      console.log("🔍 totalReserved before refund:", totalResBefore.toString());
  
      // snapshot buyer balance
      const balBefore = await ethers.provider.getBalance(buyer.address);
      console.log("🔍 buyer balance before refund:", balBefore.toString());
  
      // fast‑forward past 5 days
      await ethers.provider.send("evm_increaseTime", [FIVE_DAYS + 1]);
      await ethers.provider.send("evm_mine");
  
      // perform the refund
      const tx = await factory.refundUnagreedBuyer(1, buyer.address);
      await tx.wait();
  
      // reservation & totalReserved after
      const resAfter = await token.pendingReservations(buyer.address);
      console.log("🔍 reservation after refund:", resAfter.amount.toString());
      const totalResAfter = await token.totalReserved();
      console.log("🔍 totalReserved after refund:", totalResAfter.toString());
  
      // buyer balance after
      const balAfter = await ethers.provider.getBalance(buyer.address);
      console.log("🔍 buyer balance after refund:", balAfter.toString());
  
      // final assertions
      expect(resAfter.amount).to.equal(0);
      expect(balAfter - balBefore).to.equal(50n);
    });
  });
  

  describe("getters", () => {
    it("returns valuation, token address & seller", async () => {
      // initial valuation should just return the input when nothing's been raised
      expect(await factory.getPostMoneyValuation(1, 123)).to.equal(123);

      await factory.setSaleParameters(1, 670, 1, 300);

      await factory.connect(buyer).agreeDisclaimer(1);

      await factory.connect(buyer).buyTokens(1, 10, { value: 10 });

      expect(await factory.getPostMoneyValuation(1, 100)).to.equal(110);

      // token address & seller getter
      expect(await factory.getIPropertyToken(1)).to.equal(token.target);
      expect(await factory.getSeller(1)).to.equal(seller.address);
    });
  });
});
