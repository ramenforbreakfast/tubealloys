const { expect } = require("chai");
const { ethers } = require("hardhat");
const BigNumber = require("bignumber.js");
//const OrderBook = artifacts.require("../contracts/Orderbook")

let Controller;
let Oracle;
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
    //let date = new Date('2021.04.10');
    console.log("Owner: ", owner.address);

    roundStart = Math.round(Date.now() / 1000);
    roundEnd = Math.round(new Date('2021.04.10').getTime() / 1000);

    const controllerContract = await ethers.getContractFactory("Controller");
    Controller = await controllerContract.deploy();
    await Controller.deployed();

    const oracleContract = await ethers.getContractFactory("Oracle");
    Oracle = await oracleContract.deploy();
    await Oracle.deployed();

    await Controller.createNewSwapBook(Oracle.address, roundStart, roundEnd);
    [newBookAddress, newOracleAddress, newBookStart, newBookEnd] = await Controller.getBookInfoByIndex(0);
    console.log("Round Start: ", roundStart);
    console.log("Round End: ", roundEnd);
    console.log("Controller Address: ", Controller.address);
    console.log("Oracle Address: ", Oracle.address);
    console.log("New Orderbook Address: ", newBookAddress);
    expect(newOracleAddress).to.equal(Oracle.address);
    expect(roundStart).to.equal(roundStart);
    expect(roundEnd).to.equal(roundEnd);
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

    // Sell 28.5 variance units @ 130 strike for 2 ETH
    await Controller.sellSwapPosition(0, addr1.address, 130, ethers.utils.parseEther("2"), convertTo64x64(28.5));
    [askPrice, vaultId, seller] = await Orderbook.getOrder(0);
    [posStrike, posLong, posShort] = await Orderbook.getPosition(seller, vaultId);
    console.log("First Order - Ask Price: " + askPrice.toString() + " VaultId: " + vaultId.toString() + " Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("2"));
    expect(seller).to.equal(addr1.address);
    expect(posStrike).to.equal(130);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(28.5));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(28.5));

    // Sell 36.3 variance units @ 150 strike for 1.7 ETH
    await Controller.sellSwapPosition(0, addr2.address, 150, ethers.utils.parseEther("1.7"), convertTo64x64(36.3));
    [askPrice, vaultId, seller] = await Orderbook.getOrder(1);
    [posStrike, posLong, posShort] = await Orderbook.getPosition(seller, vaultId);
    console.log("Second Order - Ask Price: " + askPrice.toString() + " VaultId: " + vaultId.toString() + " Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("1.7"));
    expect(seller).to.equal(addr2.address);
    expect(posStrike).to.equal(150);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(36.3));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(36.3));

    // Sell 13.6 variance units @ 125 strike for 1.3 ETH
    await Controller.sellSwapPosition(0, addr2.address, 125, ethers.utils.parseEther("1.3"), convertTo64x64(13.6));
    [askPrice, vaultId, seller] = await Orderbook.getOrder(0);
    [posStrike, posLong, posShort] = await Orderbook.getPosition(seller, vaultId);
    console.log("Third Order - Ask Price: " + askPrice.toString() + " VaultId: " + vaultId.toString() + " Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("1.3"));
    expect(seller).to.equal(addr2.address);
    expect(posStrike).to.equal(125);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(13.6));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(13.6));

    // Sell 15.4 variance units @ 125 strike for 1.47 ETH
    await Controller.sellSwapPosition(0, addr2.address, 125, ethers.utils.parseEther("1.47"), convertTo64x64(15.4));
    [askPrice, vaultId, seller] = await Orderbook.getOrder(1);
    [posStrike, posLong, posShort] = await Orderbook.getPosition(seller, vaultId);
    console.log("Fourth Order - Ask Price: " + askPrice.toString() + " VaultId: " + vaultId.toString() + " Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("1.47"));
    expect(seller).to.equal(addr2.address);
    expect(posStrike).to.equal(125);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(29));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(29));
  });

  //it("Buyer of variance units should be appropriately matched with correct orders", async function () {
  //
  //});

});

