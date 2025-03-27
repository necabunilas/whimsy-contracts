const { expect } = require("chai");

describe("PropertyToken", function () {
  it("Should deploy the token and assign all tokens to the seller", async function () {
    const [seller, whimsy] = await ethers.getSigners();

    const PropertyToken = await ethers.getContractFactory("PropertyToken");
    const token = await PropertyToken.deploy("TestToken", "TTK", 1000, seller.address, whimsy.address);
    await token.deployed();

    expect(await token.balanceOf(seller.address)).to.be.above(900); // Should be 97%
    expect(await token.balanceOf(whimsy.address)).to.equal(30);     // Should be 3%
  });
});
