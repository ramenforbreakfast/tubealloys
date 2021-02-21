const { expect } = require("chai");
const { ethers } = require("hardhat");
const BigNumber = require("bignumber.js");
//const OrderBook = artifacts.require("../contracts/Orderbook")

let Controller;
let Oracle;
let defaultProvider;
let roundStart, roundEnd;
let owner, addr1, addr2, addr3, addr4;
let newBookAddress, newOracleAddress, newBookStart, newBookEnd;

function convertTo64x64(val) {
  two = BigNumber("2").pow(64);
  valBN = BigNumber(val);
  one = BigNumber("1");
  valBN = valBN.times(two);

  if (!valBN.toFixed().includes(".")) {
    return ethers.BigNumber.from(valBN.toFixed());
  }

  return ethers.BigNumber.from(valBN.plus(one).toFixed().split(".")[0]);
}

function convertFrom64x64(val) {
  two = ethers.BigNumber.from("2").pow(64);
  ten = ethers.BigNumber.from("10").pow(16);
  bigVal = val.mul(ten).div(two).toString();
  if (bigVal.length <= 16) {
    return parseFloat("0." + bigVal.padStart(16, "0")).toFixed(8).toString();
  }
  return bigVal.slice(0, bigVal.length - 16) + "." + parseFloat("0." + bigVal.slice(bigVal.length - 16, bigVal.length)).toFixed(8).toString().replace("0.", "");
}

function convertTo8DPString(val) {
  return BigNumber(val).toFixed(8).toString();
}

describe("Test Controller Contract", function () {
  it("New Orderbook Should Return Correct Initialized Values", async function () {
    [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    defaultProvider = await ethers.getDefaultProvider();
    //let date = new Date('2021.04.10');
    console.log("Owner: ", owner.address);

    roundStart = Math.round(Date.now() / 1000);

    roundEnd = Math.round((Date.now() + 86400000) / 1000);

    const controllerContract = await ethers.getContractFactory("Controller");
    Controller = await controllerContract.deploy();
    await Controller.deployed();
    console.log("Controller Address: ", Controller.address);

    const oracleContract = await ethers.getContractFactory("Oracle");
    Oracle = await oracleContract.deploy();
    await Oracle.deployed();
    console.log("Oracle Address: ", Oracle.address);

    await Controller.createNewSwapBook(Oracle.address, roundStart, roundEnd);
    [newBookAddress, newBookOwner, newOracleAddress, newBookStart, newBookEnd] = await Controller.getBookInfoByIndex(0);
    console.log("New Orderbook Address: ", newBookAddress);
    console.log("Owner Of New Book: ", newBookOwner)
    console.log("Round Start: ", newBookStart);
    console.log("Round End: ", newBookEnd);

    expect(newOracleAddress).to.equal(Oracle.address);
    expect(newBookStart).to.equal(roundStart);
    expect(newBookEnd).to.equal(roundEnd);
    // Below does not work because JS numbers are 64 bit FP versus uint256 from solidity in this case
    /*
      expect(await Controller.getBookInfoByIndex(0)).to.equal([Oracle.address, roundStart, roundEnd]);
    */
    // So roundStart and roundEnd will be returned as strings like this
    /*
    {
      "_hex": "0x6024d106"
      "_isBigNumber": true
    }
    {
      "_hex": "0x607122c0"
      "_isBigNumber": true
    }
    */
    // Waffle knows this and supports equality comparisons with Solidity uint256, but doesn't do this
    // if you are comparing an array of return values like below, you must individually compare
    // each value so Waffle understands. Perhaps there is a way to do this in a more compact way. idk
  });

  it("Minting/Selling of variance units should be reflected in the Orderbook", async function () {
    let Orderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    let askPrice, vaultId, seller;
    let posStrike, posLong, posShort;

    // Sell 28.5 variance units @ 130 strike for 0.08/unit
    await Controller.sellSwapPosition(0, addr1.address, 130, ethers.utils.parseEther("0.08"), convertTo64x64(28.5));
    [askPrice, vaultId, seller] = await Orderbook.getOrder(0);
    [posStrike, posLong, posShort] = await Orderbook.getPosition(seller, vaultId);
    console.log("First Order - Ask Price: " + ethers.utils.formatEther(askPrice) + " ETH, VaultId: " + vaultId.toString() + ", Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("0.08"));
    expect(seller).to.equal(addr1.address);
    expect(posStrike).to.equal(130);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(28.5));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(28.5));

    // Sell 36.3 variance units @ 150 strike for 0.05/unit
    await Controller.sellSwapPosition(0, addr2.address, 150, ethers.utils.parseEther("0.05"), convertTo64x64(36.3));
    [askPrice, vaultId, seller] = await Orderbook.getOrder(1);
    [posStrike, posLong, posShort] = await Orderbook.getPosition(seller, vaultId);
    console.log("Second Order - Ask Price: " + ethers.utils.formatEther(askPrice) + " ETH, VaultId: " + vaultId.toString() + ", Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("0.05"));
    expect(seller).to.equal(addr2.address);
    expect(posStrike).to.equal(150);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(36.3));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(36.3));

    // Sell 13.6 variance units @ 125 strike for 0.09/unit
    await Controller.sellSwapPosition(0, addr2.address, 125, ethers.utils.parseEther("0.09"), convertTo64x64(13.6));
    [askPrice, vaultId, seller] = await Orderbook.getOrder(0);
    [posStrike, posLong, posShort] = await Orderbook.getPosition(seller, vaultId);
    console.log("Third Order - Ask Price: " + ethers.utils.formatEther(askPrice) + " ETH, VaultId: " + vaultId.toString() + ", Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("0.09"));
    expect(seller).to.equal(addr2.address);
    expect(posStrike).to.equal(125);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(13.6));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(13.6));

    // Sell 15.4 variance units @ 125 strike for 0.09/unit
    await Controller.sellSwapPosition(0, addr2.address, 125, ethers.utils.parseEther("0.09"), convertTo64x64(15.4));
    [askPrice, vaultId, seller] = await Orderbook.getOrder(0);
    [posStrike, posLong, posShort] = await Orderbook.getPosition(seller, vaultId);
    console.log("Fourth Order - Ask Price: " + ethers.utils.formatEther(askPrice) + " ETH, VaultId: " + vaultId.toString() + ", Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("0.09"));
    expect(seller).to.equal(addr2.address);
    expect(posStrike).to.equal(125);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(29));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(29));

    // Ensure sellers cannot make orders after orderbook expiration
    // Attempting to sell another 15.4 variance units @ 125 strike for 0.09/unit
    await Orderbook.setBookRoundEnd(Math.round(Date.now() / 1000));
    await expect(Controller.sellSwapPosition(0, addr2.address, 125, ethers.utils.parseEther("0.09"), convertTo64x64(15.4))
    ).to.be.revertedWith("Cannot mint swaps for a round that has ended!");
    await Orderbook.setBookRoundEnd(roundEnd);
  });

  it("Buyer of variance units should be appropriately matched with correct orders", async function () {
    // Get quote for 40 variance units @ 130 strike
    let Orderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    let results;
    console.log("Getting quote for 40 units @ 130 strike")
    results = await Controller.getQuoteForPosition(0, 130, convertTo64x64(40));
    console.log("Quote Total Price: " + ethers.utils.formatEther(results[0]) + " ETH, " + "(" + convertFrom64x64(results[1]) + ")" + " Units Unfulfilled");
    expect(ethers.utils.formatEther(results[0])).to.equal("2.855");
    expect(convertFrom64x64(results[1])).to.equal("0.00000000");

    // Get quote for 80 variance units @ 130 strike
    console.log("Getting quote for 80 units @ 130 strike")
    results = await Controller.getQuoteForPosition(0, 130, convertTo64x64(80));
    console.log("Quote Total Price: " + ethers.utils.formatEther(results[0]) + " ETH, " + "(" + convertFrom64x64(results[1]) + ")" + " Units Unfulfilled");
    expect(ethers.utils.formatEther(results[0])).to.equal("4.095");
    expect(convertFrom64x64(results[1])).to.equal("15.20000000");

    // Purchase 2.855 ETH of 130 strike
    console.log("Purchase 2.855 ETH of 130 strike swap")
    results = await Controller.buySwapPosition(0, addr3.address, 130, ethers.utils.parseEther("2.855"));
    // non view function returns a dictionary, need to access value field
    /*
    {
      hash: '0xa3a8abacf3241fbbe00fc141ebdfb3ed70be81601a99691581909edd88b9907f',
      blockHash: '0xb363022a108355a86a7f10f56e6224399464502cbd96d615ad661d05f9f5084e',
      blockNumber: 8,
      transactionIndex: 0,
      confirmations: 1,
      from: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      gasPrice: BigNumber { _hex: '0x01dcd65000', _isBigNumber: true },
      gasLimit: BigNumber { _hex: '0x820f38', _isBigNumber: true },
      to: '0x5FbDB2315678afecb367f032d93F642f64180aa3',
      value: BigNumber { _hex: '0x00', _isBigNumber: true },
      nonce: 7,
      data: '0x8b9f9524000000000000000000000000000000000000000000000000000000000000000000000000000000000000000090f79bf6eb2c4f870365e785982e1f101e93b9060000000000000000000000000000000000000000000000000000000000000082000000000000000000000000000000000000000000000000279eff5fa1bd8000',
      r: '0x48f5b81d6e081538934013110df984b9988a10fe24499e09306227af119081b2',
      s: '0x2151bfd41a1308a84f126e32dc170d18f282491049c35f270d1ca542db577497',
      v: 62710,
      creates: null,
      chainId: 31337,
      wait: [Function (anonymous)]
    }
    */
    expect(results.value).to.equal(0); // Expect remaining position to be filled to be zero

    // Get quote for 40 variance units @ 130 strike
    console.log("Getting quote for 40 units @ 130 strike")
    results = await Controller.getQuoteForPosition(0, 130, convertTo64x64(40));
    console.log("Quote Total Price: " + ethers.utils.formatEther(results[0]) + " ETH, " + "(" + convertFrom64x64(results[1]) + ")" + " Units Unfulfilled");
    expect(ethers.utils.formatEther(results[0])).to.equal("1.24");
    expect(convertFrom64x64(results[1])).to.equal("15.20000000");

    // Ensure sellers cannot make orders after orderbook expiration
    // Attempting to sell another 15.4 variance units @ 125 strike for 0.09/unit
    await Orderbook.setBookRoundEnd(Math.round(Date.now() / 1000));
    await expect(Controller.buySwapPosition(0, addr3.address, 130, ethers.utils.parseEther("2.855"))
    ).to.be.revertedWith("Cannot purchase swaps for a round that has ended!");
    await Orderbook.setBookRoundEnd(roundEnd);
  });

  it("Testing retrieving a user's positions", async function () {
    let Orderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    let addr1Length = await Orderbook.getNumberOfUserPositions(addr1.address);
    let addr2Length = await Orderbook.getNumberOfUserPositions(addr2.address);
    let addr3Length = await Orderbook.getNumberOfUserPositions(addr3.address);

    let userStrike, userLong, userShort;
    console.log("Address 1 has " + addr1Length + "positions");
    for (i = 0; i < addr1Length; i++) {
      [userStrike, userLong, userShort] = await Controller.getUserPosition(0, addr1.address, i);
      console.log("Strike: " + userStrike + " Long: " + convertFrom64x64(userLong) + " Short: " + convertFrom64x64(userShort));
    }
    console.log("Address 2 has " + addr2Length + "positions");
    for (i = 0; i < addr2Length; i++) {
      [userStrike, userLong, userShort] = await Controller.getUserPosition(0, addr2.address, i);
      console.log("Strike: " + userStrike + " Long: " + convertFrom64x64(userLong) + " Short: " + convertFrom64x64(userShort));
    }
    console.log("Address 3 has " + addr3Length + "positions");
    for (i = 0; i < addr3Length; i++) {
      [userStrike, userLong, userShort] = await Controller.getUserPosition(0, addr3.address, i);
      console.log("Strike: " + userStrike + " Long: " + convertFrom64x64(userLong) + " Short: " + convertFrom64x64(userShort));
    }
  });

  it("Testing settlement of swaps @ end of round", async function () {
    //let Orderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    // Note to self: contract methods will not receive a gas estimation if they are reverted
    let Orderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    await expect(Controller.settleSwapBook(0)
    ).to.be.revertedWith("Controller: Cannot settle swaps before round has ended!");
    await Orderbook.setBookRoundEnd(Math.round(Date.now() / 1000));
    totalSettlement = await Controller.settleSwapBook(0);

    let addr1Length = await Orderbook.getNumberOfUserPositions(addr1.address);
    let addr2Length = await Orderbook.getNumberOfUserPositions(addr2.address);
    let addr3Length = await Orderbook.getNumberOfUserPositions(addr3.address);
    let currAddress;
    console.log("Address 1: ", addr1.address);
    console.log("Address 2: ", addr2.address);
    console.log("Address 3: ", addr3.address);
    let numberOfAddresses = await Orderbook.getNumberOfActiveAddresses();
    console.log("Number of Addresses Returned by Orderbook: ", Number(numberOfAddresses));
    for (i = 0; i < Number(numberOfAddresses); i++) {
      currAddress = await Orderbook.getAddrByIdx(i);
      console.log(currAddress);
    }

    let userSettlement;
    userSettlement = await Controller.getSettlementForUser(0, addr1.address);
    console.log("Settlement Owed To Address 1: " + ethers.utils.formatEther(userSettlement) + " ETH");

    userSettlement = await Controller.getSettlementForUser(0, addr2.address);
    console.log("Settlement Owed To Address 2: " + ethers.utils.formatEther(userSettlement) + " ETH");

    userSettlement = await Controller.getSettlementForUser(0, addr3.address);
    console.log("Settlement Owed To Address 3: " + ethers.utils.formatEther(userSettlement) + " ETH");
  });
});

