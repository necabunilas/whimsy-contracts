const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("HelloBase", function () {
  let Hello, hello, owner;

  beforeEach(async function () {
    [owner] = await ethers.getSigners();
    Hello = await ethers.getContractFactory("HelloBase");
    hello = await Hello.deploy();
    await hello.deployed();
  });

  it("has initial greeting", async function () {
    expect(await hello.greet()).to.equal("Hello, Base!");
  });

  it("lets you set a new greeting", async function () {
    await hello.setGreet("Hi!");
    expect(await hello.greet()).to.equal("Hi!");
  });
});
