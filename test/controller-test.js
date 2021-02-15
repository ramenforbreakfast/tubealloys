const { expect } = require("chai");
const BigNumber = require('bignumber.js');
const { web3 } = require("hardhat");
const controllerContract = artifacts.require("../contracts/Controller");
const oracleContract = artifacts.require("../contracts/Oracle");

let Controller;
let Oracle;
let roundEnd;
let owner, addr1, addr2, addr3, addr4;

beforeEach(async function () {
  [owner, addr1, addr2, addr3, addr4] = await web3.eth.getAccounts();
  //let date = new Date('2021.04.10');
  roundEnd = Math.round(new Date('2021.04.10').getTime() / 1000);

  Controller = await controllerContract.new();
  Oracle = await oracleContract.new();
});


describe("Test Orderbook Creation", function () {
  it("New Orderbook Should Return Correct Initialized Values", async function () {
    let roundStart = Math.round(Date.now() / 1000);
    console.log("Round Start: ", roundStart);
    console.log("Round End: ", roundEnd);
    console.log("Controller Address: ", Controller.address);
    console.log("Oracle Address: ", Oracle.address);
    await Controller.createNewSwapBook(Oracle.address, roundStart, roundEnd);
    let result;
    result = await Controller.getBookInfoByIndex(0);
    console.log("Orderbook Oracle Address: ", result[0]);
    console.log("Orderbook roundStart: ", result[1].toString());
    console.log("Orderbook roundEnd: ", result[2].toString());
    expect(result[0]).to.equal(Oracle.address);
    expect(result[1].toNumber()).to.equal(roundStart);
    expect(result[2].toNumber()).to.equal(roundEnd);
  });
});

describe("Test Selling/Minting Variance", function () {
  it("Minting variance should create a sell order in the Orderbook", async function () {
    // Sell 2.85 ETH of variance @ 130 strike for 2 ETH.
    var testnum = new BigNumber(500.2);
    var denominator = new BigNumber(2);
    denominator = denominator.exponentiatedBy(64);
    testnum = testnum.multipliedBy(denominator);
    console.log("BigNumber JS denominator: ", denominator.toString(10));
    console.log("BigNumber JS string: ", testnum.toString(10));
    var BNtestnum = web3.utils.toBN(testnum.toString(16));
    console.log(BNtestnum);

    await Controller.sellSwapPosition(0, addr1, 130, web3.utils.toWei("2"), web3.utils.toHex(28.5 * 2 ** 64));
    let result;
    result = await Controller.getOrder(0);
    console.log("Order Ask Price: ", result[0]);
    console.log("Variance VaultId: ", result[1]);
    console.log("Seller Address: ", result[2]);
  })
})

