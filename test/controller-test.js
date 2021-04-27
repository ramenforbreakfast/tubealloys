const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const BigNumber = require("bignumber.js");
//const OrderBook = artifacts.require("../contracts/Orderbook")

let Pool;
let Controller;
let Oracle;
let Orderbook;
let defaultProvider;
let roundStart, roundEnd;
let owner, addr1, addr2, addr3, addr4;
let newBookID, newBookAddress, newOracleAddress, newBookStart, newBookEnd, newBookIV;

let formatSpecs = { signed: false, width: 256, decimals: 8, name: "eightFixed" };
//let eightFixed = ethers.fixedFormat.from(formatSpecs);

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

function waitUntil(thisTime) {
  while (new Date().getTime() <= (thisTime * 1000)) true;
}

function printOrder(orderID, query) {
  console.log("Order " + orderID)
  console.log("Current Ask: " + ethers.utils.formatEther(query[2].div(1e8)) + " ETH, Current Units: " + (query[1] / 1e8).toString())
  console.log("Belonging to: " + query[0] + " @ position index: " + query[5].toString());
}

function printPosition(address, query) {
  console.log(address);
  console.log("Variance Position - Strike: " + (query[0] / 1e8).toString() + " Long: " + (query[1] / 1e8).toString() + " Short: " + (query[2] / 1e8).toString());
}

describe("Test Controller Contract", function () {
  it("New Orderbook Should Return Correct Initialized Values", async function () {
    /* DO NOT DO THIS 
     * getDefaultProvider sets the provider to a new provider
     * When I had this statement in the code, it reset the provider hardhat already initializes and had no
     * knowledge of the current state of the hardhat chain (since it's not synced), so all my address balances were zero
    defaultProvider = await ethers.getDefaultProvider();
    console.log(defaultProvider);
    */

    let i;
    let id, next, data;
    let userAddresses = await ethers.getSigners();
    [owner, addr1, addr2, addr3, addr4] = userAddresses;
    console.log("Showing First 5 Addresses...")
    for (i = 0; i < 5; i++) {
      console.log("Address: ", userAddresses[i].address);
      console.log("Balance: ", (await userAddresses[i].getBalance()).toString());
    }

    roundStart = Math.round(Date.now() / 1000);

    roundEnd = Math.round((Date.now() + 45000) / 1000);

    const poolContract = await ethers.getContractFactory("Pool");
    Pool = await upgrades.deployProxy(poolContract);
    await Pool.deployed();
    console.log("Pool Address: ", Pool.address);

    const controllerContract = await ethers.getContractFactory("Controller");
    Controller = await upgrades.deployProxy(controllerContract, [Pool.address]);
    await Controller.deployed();
    console.log("Controller Address: ", Controller.address);
    await Pool.transferOwnership(Controller.address);

    const oracleContract = await ethers.getContractFactory("Oracle");
    Oracle = await oracleContract.deploy();
    await Oracle.deployed();
    console.log("Oracle Address: ", Oracle.address);

    const orderBookContract = await ethers.getContractFactory("Orderbook");
    let initBookIV = await Oracle.getLatestImpliedVariance();
    newBookID = "ETH-" + initBookIV + "-" + roundStart + "-" + roundEnd;
    console.log("New Book Name: ", newBookID);
    Orderbook = await upgrades.deployProxy(orderBookContract, [roundStart, roundEnd, initBookIV, Oracle.address]);
    await Orderbook.deployed();
    await Orderbook.transferOwnership(Controller.address);

    console.log("Orderbook Address: ", Orderbook.address);
    await Controller.addNewSwapBook(newBookID, Orderbook.address);
    [newBookAddress, newBookStart, newBookEnd, newBookIV, newOracleAddress] = await Controller.getBookInfoByName(newBookID);
    console.log("New Orderbook Address: ", newBookAddress);
    console.log("Round Start: ", newBookStart.toString());
    console.log("Round End: ", newBookEnd.toString());

    expect(newBookStart).to.equal(roundStart);
    expect(newBookEnd).to.equal(roundEnd);
    expect(newOracleAddress).to.equal(Oracle.address);
    expect(newBookIV).to.equal(initBookIV);

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

  it("Ensure users cannot call functions on undeployed orderbooks", async function () {
    let badBookID = "Idontexist";
    await expect(Controller.connect(owner).settleSwapBook(badBookID)
    ).to.be.revertedWith("Controller: Cannot perform operation on undeployed orderbook!");

    await expect(Controller.connect(owner).getSettlementForUser(badBookID, addr1.address)
    ).to.be.revertedWith("Controller: Cannot perform operation on undeployed orderbook!");

    await expect(Controller.connect(addr1).getQuoteForPosition(badBookID, 1.3e8, 28.55e8)
    ).to.be.revertedWith("Controller: Cannot perform operation on undeployed orderbook!");

    await expect(Controller.connect(addr1).buySwapPosition(badBookID, addr1.address, 1.3e8, ethers.utils.parseEther("2"))
    ).to.be.revertedWith("Controller: Cannot perform operation on undeployed orderbook!");

    await expect(Controller.connect(addr1).sellSwapPosition(badBookID, addr1.address, 1.3e8, ethers.utils.parseEther("0.08"), 28.55e8)
    ).to.be.revertedWith("Controller: Cannot perform operation on undeployed orderbook!");

    await expect(Controller.connect(addr1).redeemSwapPositions(badBookID, addr1.address)
    ).to.be.revertedWith("Controller: Cannot perform operation on undeployed orderbook!");
  });

  it("Ensure users cannot settle or redeem swaps before end date", async function () {
    await expect(Controller.connect(owner).settleSwapBook(newBookID)
    ).to.be.revertedWith("Controller: Cannot settle swaps before round has ended!");

    await expect(Controller.connect(addr1).redeemSwapPositions(newBookID, addr1.address)
    ).to.be.revertedWith("Controller: Cannot redeem swap before round has been settled!");
  });

  it("Ensure users can only buy/sell/redeem positions if they are the sender", async function () {
    await expect(Controller.connect(addr2).buySwapPosition(newBookID, addr1.address, 1.3e8, ethers.utils.parseEther("2"))
    ).to.be.revertedWith("Controller: Cannot perform operation for another user!");

    await expect(Controller.connect(addr2).sellSwapPosition(newBookID, addr1.address, 1.3e8, ethers.utils.parseEther("0.08"), 28.55e8)
    ).to.be.revertedWith("Controller: Cannot perform operation for another user!");

    await expect(Controller.connect(addr2).redeemSwapPositions(newBookID, addr1.address)
    ).to.be.revertedWith("Controller: Cannot perform operation for another user!");
  });

  it("Deposit/Withdrawal of user funds", async function () {
    await Pool.connect(addr1).deposit({ value: ethers.utils.parseEther("2.85") });
    expect(await Pool.getUserBalance(addr1.address)).to.equal(ethers.utils.parseEther("2.85"));
    expect(await addr1.getBalance()).to.equal(ethers.utils.parseEther("9997.15"));

    await Pool.connect(addr2).deposit({ value: ethers.utils.parseEther("10") });
    expect(await Pool.getUserBalance(addr2.address)).to.equal(ethers.utils.parseEther("10"));
    expect(await addr2.getBalance()).to.equal(ethers.utils.parseEther("9990"));

    await Pool.connect(addr3).deposit({ value: ethers.utils.parseEther("5") });
    expect(await Pool.getUserBalance(addr3.address)).to.equal(ethers.utils.parseEther("5"));
    expect(await addr3.getBalance()).to.equal(ethers.utils.parseEther("9995"));
  });

  it("Ensure users cannot spend more than they have", async function () {
    // Attempt to sell 28.6 variance units (2.86 ETH of collateral) with only 2.85 ETH deposited
    await expect(Controller.connect(addr1).sellSwapPosition(newBookID, addr1.address, 1.3e8, ethers.utils.parseEther("2.288"), 28.6e8)
    ).to.be.revertedWith("Controller: User has insufficient funds to collateralize swaps!");
    // Verify that address 1 balance was not affected by reverted transaction
    expect(await Pool.connect(addr1).getUserBalance(addr1.address)).to.equal(ethers.utils.parseEther("2.85"));

    // Attempt to purchase 2.85001 ETH worth of swaps with only 2.85 ETH deposited
    await expect(Controller.connect(addr1).buySwapPosition(newBookID, addr1.address, 1.3e8, ethers.utils.parseEther("2.85001"))
    ).to.be.revertedWith("Controller: User has insufficient funds to purchase swaps!");
    // Verify that address 1 balance was not affected by reverted transaction
    expect(await Pool.connect(addr1).getUserBalance(addr1.address)).to.equal(ethers.utils.parseEther("2.85"));
  });

  it("Minting/Selling of variance units should be reflected in the Orderbook", async function () {
    let sellEvent, orderID, orderQuery;
    let sellerAddr, currUnits, currAsk, totalUnits, totalAsk, posIdx, filled;
    let posStrike, posLong, posShort;
    let sellEventFilter = Controller.filters.SellOrder();

    // Sell 28.5 variance units @ 130 strike for 0.08/unit
    //let gasEstimate = await Controller.estimateGas.sellSwapPosition(newBookID, addr1.address, 130, ethers.utils.parseEther("0.08"), convertTo64x64(28.5));
    //console.log('Gas Estimate for sellSwapPosition: ', gasEstimate.toString());
    await Controller.connect(addr1).sellSwapPosition(newBookID, addr1.address, 1.3e8, ethers.utils.parseEther("2.28"), 28.5e8);
    sellEvent = await Controller.queryFilter(sellEventFilter, "latest");
    orderID = sellEvent[0].args.orderID;

    orderQuery = [sellerAddr, currUnits, currAsk, totalUnits, totalAsk, posIdx, filled] = await Orderbook.getOrder(orderID);
    positionQuery = [posStrike, posLong, posShort] = await Orderbook.getPosition(sellerAddr, posIdx);
    printOrder(orderID, orderQuery);
    printPosition(positionQuery);
    expect(totalAsk).to.equal(currAsk);
    expect(totalUnits).to.equal(currUnits);
    expect(totalAsk.div(totalUnits)).to.equal(ethers.utils.parseEther("0.08"));
    expect(sellerAddr).to.equal(addr1.address);
    expect(posStrike).to.equal(1.3e8);
    expect(posLong).to.equal(28.5e8);
    expect(posShort).to.equal(28.5e8);

    // Sell 36.3 variance units @ 150 strike for 0.05/unit
    await Controller.connect(addr2).sellSwapPosition(newBookID, addr2.address, 1.5e8, ethers.utils.parseEther("1.815"), 36.3e8);
    sellEvent = await Controller.queryFilter(sellEventFilter, "latest");
    orderID = sellEvent[0].args.orderID;

    orderQuery = [sellerAddr, currUnits, currAsk, totalUnits, totalAsk, posIdx, filled] = await Orderbook.getOrder(orderID);
    positionQuery = [posStrike, posLong, posShort] = await Orderbook.getPosition(sellerAddr, posIdx);
    printOrder(orderID, orderQuery);
    printPosition(positionQuery);
    expect(totalAsk).to.equal(currAsk);
    expect(totalUnits).to.equal(currUnits);
    expect(totalAsk.div(totalUnits)).to.equal(ethers.utils.parseEther("0.05"));
    expect(sellerAddr).to.equal(addr2.address);
    expect(posStrike).to.equal(1.5e8);
    expect(posLong).to.equal(36.3e8);
    expect(posShort).to.equal(36.3e8);

    // Sell 13.6 variance units @ 125 strike for 0.09/unit
    await Controller.connect(addr2).sellSwapPosition(newBookID, addr2.address, 1.25e8, ethers.utils.parseEther("1.224"), 13.6e8);
    sellEvent = await Controller.queryFilter(sellEventFilter, "latest");
    orderID = sellEvent[0].args.orderID;

    orderQuery = [sellerAddr, currUnits, currAsk, totalUnits, totalAsk, posIdx, filled] = await Orderbook.getOrder(orderID);
    positionQuery = [posStrike, posLong, posShort] = await Orderbook.getPosition(sellerAddr, posIdx);
    printOrder(orderID, orderQuery);
    printPosition(positionQuery);
    expect(totalAsk).to.equal(currAsk);
    expect(totalUnits).to.equal(currUnits);
    expect(totalAsk.div(totalUnits)).to.equal(ethers.utils.parseEther("0.09"));
    expect(sellerAddr).to.equal(addr2.address);
    expect(posStrike).to.equal(1.25e8);
    expect(posLong).to.equal(13.6e8);
    expect(posShort).to.equal(13.6e8);

    // Sell 15.4 variance units @ 125 strike for 0.09/unit
    await Controller.connect(addr2).sellSwapPosition(newBookID, addr2.address, 1.25e8, ethers.utils.parseEther("1.386"), 15.4e8);
    sellEvent = await Controller.queryFilter(sellEventFilter, "latest");
    orderID = sellEvent[0].args.orderID;

    orderQuery = [sellerAddr, currUnits, currAsk, totalUnits, totalAsk, posIdx, filled] = await Orderbook.getOrder(orderID);
    positionQuery = [posStrike, posLong, posShort] = await Orderbook.getPosition(sellerAddr, posIdx);
    printOrder(orderID, orderQuery);
    printPosition(positionQuery);
    expect(totalAsk).to.equal(currAsk);
    expect(totalUnits).to.equal(currUnits);
    expect(totalAsk.div(totalUnits)).to.equal(ethers.utils.parseEther("0.09"));
    expect(sellerAddr).to.equal(addr2.address);
    expect(posStrike).to.equal(1.25e8);
    expect(posLong).to.equal(29e8);
    expect(posShort).to.equal(29e8);
  });

  it("Testing correct order matching for swap purchase quotes and purchase orders", async function () {
    let results;
    let orderIDS;
    let buyEvent;
    let buyEventFilter = Controller.filters.BuyOrder();

    console.log("GETTING quote for 40 units @ 130 strike");
    results = await Controller.connect(addr3).getQuoteForPosition(newBookID, 1.3e8, 40e8);
    console.log("(" + results[0] / 1e8 + ")" + " Units Left Unmatched" + ", Units to Partially Purchase From Last Order: " + results[1] / 1e8);
    expect(results[0] / 1e8).to.equal(0);
    expect(results[1] / 1e8).to.equal(11.5);
    orderIDS = results[2];
    for (let i = 0; i < 10; i++) {
      if (orderIDS[i] != 0) {
        orderQuery = await Orderbook.getOrder(orderIDS[i]);
        printOrder(orderIDS[i], orderQuery);
      }
    }

    // Get quote for 80 variance units @ 130 strike
    console.log("GETTING quote for 80 units @ 130 strike");
    results = await Controller.connect(addr3).getQuoteForPosition(newBookID, 1.3e8, 80e8);
    console.log("(" + results[0] / 1e8 + ")" + " Units Left Unmatched" + ", Units to Partially Purchase From Last Order: " + results[1] / 1e8);
    expect(results[0] / 1e8).to.equal(15.2);
    expect(results[1] / 1e8).to.equal(0);
    orderIDS = results[2];
    for (let i = 0; i < 10; i++) {
      if (orderIDS[i] != 0) {
        orderQuery = await Orderbook.getOrder(orderIDS[i]);
        printOrder(orderIDS[i], orderQuery);
      }
    }

    // Purchase 2.855 ETH of 130 strike
    // non view function returns a dictionary, need to access value field
    console.log("ATTEMPT to purchase 2.855 ETH of 130 strike swap");
    await Controller.connect(addr3).buySwapPosition(newBookID, addr3.address, 1.3e8, ethers.utils.parseEther("2.855"));
    buyEvent = await Controller.queryFilter(buyEventFilter, "latest");
    // Expect remaining position to be filled to be zero
    expect(buyEvent[0].args.remainder).to.equal(0);

    // Get quote for 40 variance units @ 130 strike
    console.log("GETTING quote for 40 units @ 130 strike");
    results = await Controller.connect(addr3).getQuoteForPosition(newBookID, 1.3e8, 40e8);
    console.log("(" + results[0] / 1e8 + ")" + " Units Left Unmatched" + ", Units to Partially Purchase From Last Order: " + results[1] / 1e8);
    expect(results[0] / 1e8).to.equal(15.19999972);
    expect(results[1] / 1e8).to.equal(0);
    orderIDS = results[2];
    for (let i = 0; i < 10; i++) {
      if (orderIDS[i] != 0) {
        orderQuery = await Orderbook.getOrder(orderIDS[i]);
        printOrder(orderIDS[i], orderQuery);
      }
    }

    // Test purchase here to verify that the sell function transfers the remainder back to the user if the buy order could not be completely filled.
    // Attempt to purchase 1.30 ETH worth of swaps @ 130 to exceed the quoted supply of 15.2 units for 1.24 ETH.
    console.log("ATTEMPT to purchase 1.30 ETH of 130 strike swap");
    await Controller.connect(addr3).buySwapPosition(newBookID, addr3.address, 1.3e8, ethers.utils.parseEther("1.30"));
    buyEvent = await Controller.queryFilter(buyEventFilter, "latest");
    expect(buyEvent[0].args.remainder).to.equal(ethers.utils.parseEther("0.06"));

    // Expect remaining funds in our platform to be 0.905 ETH after purchase.
    let userBalance = await Pool.connect(addr3).getUserBalance(addr3.address);
    expect(userBalance).to.equal(ethers.utils.parseEther("0.905"));
  });

  it("Testing retrieval of user positions", async function () {
    let addr1Length = Number(await Orderbook.getNumberOfUserPositions(addr1.address));
    let addr2Length = Number(await Orderbook.getNumberOfUserPositions(addr2.address));
    let addr3Length = Number(await Orderbook.getNumberOfUserPositions(addr3.address));

    let userStrike, userLong, userShort;
    console.log("Address 1 has " + addr1Length + " positions");
    expect(addr1Length).to.equal(1);
    [userStrike, userLong, userShort] = await Orderbook.getPosition(addr1.address, 0);
    console.log("Strike: " + userStrike + " Long: " + userLong / 1e8 + " Short: " + userShort / 1e8);
    expect(userLong).to.equal(0);
    expect(userShort).to.equal(28.5e8);

    console.log("Address 2 has " + addr2Length + " positions");
    expect(addr2Length).to.equal(2);
    [userStrike, userLong, userShort] = await Orderbook.getPosition(addr2.address, 0);
    console.log("Strike: " + userStrike + " Long: " + userLong / 1e8 + " Short: " + userShort / 1e8);
    expect(userLong).to.equal(0);
    expect(userShort).to.equal(36.3e8);
    [userStrike, userLong, userShort] = await Orderbook.getPosition(addr2.address, 1);
    console.log("Strike: " + userStrike + " Long: " + userLong / 1e8 + " Short: " + userShort / 1e8);
    expect(userLong).to.equal(29e8);
    expect(userShort).to.equal(29e8);

    console.log("Address 3 has " + addr3Length + " positions");
    expect(addr3Length).to.equal(2);
    [userStrike, userLong, userShort] = await Orderbook.getPosition(addr3.address, 0);
    console.log("Strike: " + userStrike + " Long: " + userLong / 1e8 + " Short: " + userShort / 1e8);
    expect(userLong).to.equal(28.5e8);
    expect(userShort).to.equal(0);
    [userStrike, userLong, userShort] = await Orderbook.getPosition(addr3.address, 1);
    console.log("Strike: " + userStrike + " Long: " + userLong / 1e8 + " Short: " + userShort / 1e8);
    expect(userLong).to.equal(36.3e8);
    expect(userShort).to.equal(0);
  });

  it("Testing settlement of swaps @ end of round", async function () {
    //let Orderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    // Note to self: contract methods will not receive a gas estimation if they are reverted
    await expect(Controller.connect(owner).settleSwapBook(newBookID)
    ).to.be.revertedWith("Controller: Cannot settle swaps before round has ended!");

    console.log("Waiting for settlement time...");
    waitUntil(roundEnd);
    await Controller.connect(owner).settleSwapBook(newBookID);

    let currAddress;
    let numberOfAddresses = Number(await Orderbook.getNumberOfActiveAddresses());
    console.log("Number of Addresses Returned by Orderbook: ", numberOfAddresses);
    for (i = 0; i < numberOfAddresses; i++) {
      currAddress = await Orderbook.getAddrByIdx(i);
      console.log(currAddress);
    }

    let userSettlement;
    userSettlement = await Controller.getSettlementForUser(newBookID, addr1.address);
    console.log("Settlement Owed To Address 1: " + ethers.utils.formatEther(userSettlement) + " ETH");
    expect(ethers.utils.formatEther(userSettlement)).to.equal("2.28");

    userSettlement = await Controller.getSettlementForUser(newBookID, addr2.address);
    console.log("Settlement Owed To Address 2: " + ethers.utils.formatEther(userSettlement) + " ETH");
    expect(ethers.utils.formatEther(userSettlement)).to.equal("6.53");

    userSettlement = await Controller.getSettlementForUser(newBookID, addr3.address);
    console.log("Settlement Owed To Address 3: " + ethers.utils.formatEther(userSettlement) + " ETH");
    expect(ethers.utils.formatEther(userSettlement)).to.equal("0.57");
  });

  it("Ensure buy/sell/settlement functions cannot be called after settlement", async function () {
    await expect(Controller.connect(addr2.address).buySwapPosition(newBookID, addr2.address, 1.3e8, ethers.utils.parseEther("2.855"))
    ).to.be.revertedWith("Cannot purchase swaps for a round that has ended!");

    await expect(Controller.connect(addr2.address).sellSwapPosition(newBookID, addr2.address, 1.3e8, ethers.utils.parseEther("0.08"), 28.5e8)
    ).to.be.revertedWith("Cannot mint swaps for a round that has ended!");

    await expect(Controller.connect(owner).settleSwapBook(newBookID)
    ).to.be.revertedWith("Cannot settle swaps for an already settled orderbook!");
  });

  it("Ensure users may redeem positions and withdraw their funds", async function () {
    expect(await Pool.connect(addr1).getUserBalance(addr1.address)
    ).to.equal(0);
    expect(await Pool.connect(addr2).getUserBalance(addr2.address)
    ).to.equal(ethers.utils.parseEther("3.47"));
    expect(await Pool.connect(addr3).getUserBalance(addr3.address)
    ).to.equal(ethers.utils.parseEther("0.905"));

    await Controller.connect(addr1).redeemSwapPositions(newBookID, addr1.address);
    await Controller.connect(addr2).redeemSwapPositions(newBookID, addr2.address);
    await Controller.connect(addr3).redeemSwapPositions(newBookID, addr3.address);

    await Controller.connect(addr1).redeemOrderPayments(newBookID, addr1.address)
    await Controller.connect(addr2).redeemOrderPayments(newBookID, addr2.address);
    await Controller.connect(addr3).redeemOrderPayments(newBookID, addr3.address);

    expect(await Pool.connect(addr1).getUserBalance(addr1.address)
    ).to.equal(ethers.utils.parseEther("4.56"));
    expect(await Pool.connect(addr2).getUserBalance(addr2.address)
    ).to.equal(ethers.utils.parseEther("11.815"));
    expect(await Pool.connect(addr3).getUserBalance(addr3.address)
    ).to.equal(ethers.utils.parseEther("1.475"));

    await Pool.connect(addr1).withdraw(ethers.utils.parseEther("1"));
    expect(await addr1.getBalance()
    ).to.equal(ethers.utils.parseEther("9998.15"));

    await Pool.connect(addr1).withdraw(ethers.utils.parseEther("3.56"));
    expect(await addr1.getBalance()
    ).to.equal(ethers.utils.parseEther("10001.71"));

    await Pool.connect(addr2).withdraw(ethers.utils.parseEther("11.815"));
    expect(await addr2.getBalance()
    ).to.equal(ethers.utils.parseEther("10001.815"));

    await Pool.connect(addr3).withdraw(ethers.utils.parseEther("1.475"));
    expect(await addr3.getBalance()
    ).to.equal(ethers.utils.parseEther("9996.475"));
  });

  it.only("Gas stress test", async function () {
    let i, j, k;
    let userAddresses = await ethers.getSigners();
    roundStart = Math.round(Date.now() / 1000);
    // Block 
    roundEnd = Math.round((Date.now() + 9000000) / 1000);

    const poolContract = await ethers.getContractFactory("Pool");
    Pool = await upgrades.deployProxy(poolContract);
    await Pool.deployed();
    console.log("Pool Address: ", Pool.address);

    const controllerContract = await ethers.getContractFactory("Controller");
    Controller = await upgrades.deployProxy(controllerContract, [Pool.address]);
    await Controller.deployed();
    console.log("Controller Address: ", Controller.address);
    await Pool.transferOwnership(Controller.address);

    const oracleContract = await ethers.getContractFactory("Oracle");
    Oracle = await oracleContract.deploy();
    await Oracle.deployed();
    console.log("Oracle Address: ", Oracle.address);

    const orderBookContract = await ethers.getContractFactory("Orderbook");
    let initBookIV = await Oracle.getLatestImpliedVariance();
    newBookID = "ETH-" + initBookIV + "-" + roundStart + "-" + roundEnd;
    console.log("New Book Name: ", newBookID);
    Orderbook = await upgrades.deployProxy(orderBookContract, [roundStart, roundEnd, initBookIV, Oracle.address]);
    await Orderbook.deployed();
    await Orderbook.transferOwnership(Controller.address);

    console.log("Orderbook Address: ", Orderbook.address);
    await Controller.addNewSwapBook(newBookID, Orderbook.address);
    [newBookAddress, newBookStart, newBookEnd, newBookIV, newOracleAddress] = await Controller.getBookInfoByName(newBookID);
    console.log("New Orderbook Address: ", newBookAddress);
    console.log("Round Start: ", newBookStart.toString());
    console.log("Round End: ", newBookEnd.toString());
    expect(newBookStart).to.equal(roundStart);
    expect(newBookEnd).to.equal(roundEnd);
    expect(newBookIV).to.equal(initBookIV);
    expect(newOracleAddress).to.equal(Oracle.address);

    console.log("Depositing Pool Funds For 1000 Addresses...")
    let currAddress, buyTx, buyReceipt, txBlock;
    for (i = 0; i < userAddresses.length; i++) {
      currAddress = userAddresses[i];
      buyTx = await Pool.connect(currAddress).deposit({ value: ethers.utils.parseEther("10") });
      if ((i % 100) == 0) {
        try {
          buyReceipt = await buyTx.wait();
          txBlock = await ethers.provider.getBlock(buyReceipt.blockNumber)
          console.log(txBlock.timestamp);
        } catch (e) {
          console.log(`Transaction Receipt Not Received!\n${e}`);
        }
      }
      expect(await Pool.getUserBalance(currAddress.address)).to.equal(ethers.utils.parseEther("10"));
      expect(await currAddress.getBalance()).to.equal(ethers.utils.parseEther("9990"));
    }

    console.log("Selling Swap Positions For 500 Addresses...")
    //txBlock = await ethers.provider.getBlock(await ethers.provider.getBlockNumber());
    //console.log("Timestamp BEFORE Selling: ", txBlock.timestamp);
    let posStrike, posLong, posShort, sellPrice, positionQuery, positionLength;
    let sellEvent, orderID, orderQuery;
    let sellEventFilter = Controller.filters.SellOrder();

    for (i = 0; i < 25; i++) {
      for (j = 0; j < 10; j++) {
        // Sold positions will be made by the first 25 addresses
        currAddress = userAddresses[i * 10 + j];
        // sell these swaps for 0.002/unit, 0.0021, 0.0022... up to j
        // sell price is for the whole 10 units, so divide by 100
        sellPrice = (2 + 0.1 * j) / 100;
        // make strikes 1.3 - j(0.01)
        await Controller.connect(currAddress).sellSwapPosition(newBookID, currAddress.address, (1.3e8 - (j * 1e6)), ethers.utils.parseEther(sellPrice.toString()), 10e8);

        [posStrike, posLong, posShort] = await Orderbook.connect(currAddress).getPosition(currAddress.address, 0);
        expect(posStrike).to.equal(1.3e8 - (j * 1e6));
        expect(posLong).to.equal(10e8);
        expect(posShort).to.equal(10e8);

        console.log(i * 10 + j);
        positionLength = Number(await Orderbook.getNumberOfUserPositions(currAddress.address));
        for (k = 0; k < positionLength; k++) {
          positionQuery = await Orderbook.connect(currAddress).getPosition(currAddress.address, k);
          printPosition(currAddress.address, positionQuery);
        }
      }
    }
    for (i = 25; i < 50; i++) {
      for (j = 0; j < 10; j++) {
        // Sold positions will be made by the next 25 addresses
        currAddress = userAddresses[i * 10 + j];
        // sell these swaps for 0.0015/unit, 0.0016, 0.0017... up to j
        // sell price is for the whole 10 units, so divide by 100
        sellPrice = (1.5 + 0.1 * j) / 100;
        // make strikes 1.4 - j(0.01)
        await Controller.connect(currAddress).sellSwapPosition(newBookID, currAddress.address, (1.4e8 - (j * 1e6)), ethers.utils.parseEther(sellPrice.toString()), 10e8);

        [posStrike, posLong, posShort] = await Orderbook.connect(currAddress).getPosition(currAddress.address, 0);
        expect(posStrike).to.equal(1.4e8 - (j * 1e6));
        expect(posLong).to.equal(10e8);
        expect(posShort).to.equal(10e8);

        console.log(i * 10 + j);
        positionLength = Number(await Orderbook.getNumberOfUserPositions(currAddress.address));
        for (k = 0; k < positionLength; k++) {
          positionQuery = await Orderbook.connect(currAddress).getPosition(currAddress.address, k);
          printPosition(currAddress.address, positionQuery);
        }
      }
    }

    console.log("\nBUYING Swap Positions for Address 500-524...")
    let buyPrice;
    for (i = 0; i < 25; i++) {
      buyPrice = 0;
      currAddress = userAddresses[i + 500];
      buyPrice = 0.1225 // buy 50% of the first 250 sell orders @ 1.3
      buyTx = await Controller.connect(currAddress).buySwapPosition(newBookID, currAddress.address, 1.2e8, ethers.utils.parseEther(buyPrice.toString()));
      try {
        buyReceipt = await buyTx.wait();
      } catch (e) {
        console.log(`Transaction Receipt Not Received!\n${e}`);
      }
    }

    for (i = 0; i < 25; i++) {
      console.log(i);
      currAddress = userAddresses[i + 500];
      positionLength = Number(await Orderbook.getNumberOfUserPositions(currAddress.address));
      for (j = 0; j < positionLength; j++) {
        positionQuery = await Orderbook.connect(currAddress).getPosition(currAddress.address, j);
        printPosition(currAddress.address, positionQuery);
      }
    }

    console.log("\nBUYING Swap Positions for Address 525-549...")
    for (i = 25; i < 50; i++) {
      buyPrice = 0;
      currAddress = userAddresses[i + 500];
      buyPrice = 0.3175;// buy 50% of the first 250 sell orders @ 1.3 and 100% of the next 250 @ 1.4
      buyTx = await Controller.connect(currAddress).buySwapPosition(newBookID, currAddress.address, 1.2e8, ethers.utils.parseEther(buyPrice.toString()));
      try {
        buyReceipt = await buyTx.wait();
      } catch (e) {
        console.log(`Transaction Receipt Not Received!\n${e}`);
      }
    }

    for (i = 25; i < 50; i++) {
      console.log(i);
      currAddress = userAddresses[i + 500];
      positionLength = Number(await Orderbook.getNumberOfUserPositions(currAddress.address));
      for (j = 0; j < positionLength; j++) {
        positionQuery = await Orderbook.connect(currAddress).getPosition(currAddress.address, j);
        printPosition(currAddress.address, positionQuery);
      }
    }

    currAddress = userAddresses[550];
    buyPrice = 0.3175;
    buyTx = await Controller.connect(currAddress).buySwapPosition(newBookID, currAddress.address, 1.2e8, ethers.utils.parseEther(buyPrice.toString()));
    try {
      buyReceipt = await buyTx.wait();
    } catch (e) {
      console.log(`Transaction Receipt Not Received!\n${e}`);
    }

    console.log(550);
    positionLength = Number(await Orderbook.getNumberOfUserPositions(currAddress.address));
    for (j = 0; j < positionLength; j++) {
      positionQuery = await Orderbook.connect(currAddress).getPosition(currAddress.address, j);
      printPosition(currAddress.address, positionQuery);
    }

  })

});

