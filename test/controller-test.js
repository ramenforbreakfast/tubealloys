const { expect } = require("chai");
const { ethers } = require("hardhat");
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
    /* DO NOT DO THIS 
     * getDefaultProvider sets the provider to a new provider
     * When I had this statement in the code, it reset the provider hardhat already initializes and had no
     * knowledge of the current state of the hardhat chain (since it's not synced), so all my address balances were zero
    defaultProvider = await ethers.getDefaultProvider();
    console.log(defaultProvider);
    */

    let i;
    let userAddresses = await ethers.getSigners();
    [owner, addr1, addr2, addr3, addr4] = userAddresses;
    for (i = 0; i < userAddresses.length; i++) {
      console.log("Address: ", userAddresses[i].address);
      console.log("Balance: ", (await userAddresses[i].getBalance()).toString());
    }

    roundStart = Math.round(Date.now() / 1000);

    roundEnd = Math.round((Date.now() + 30000) / 1000);

    const poolContract = await ethers.getContractFactory("Pool");
    Pool = await poolContract.deploy();
    await Pool.deployed();
    console.log("Pool Address: ", Pool.address);

    const controllerContract = await ethers.getContractFactory("Controller");
    Controller = await controllerContract.deploy(Pool.address);
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
    Orderbook = await orderBookContract.deploy(roundStart, roundEnd, Oracle.address, initBookIV);
    await Orderbook.deployed();
    await Orderbook.transferOwnership(Controller.address);

    console.log("Orderbook Address: ", Orderbook.address);
    await Controller.addNewSwapBook(newBookID, Orderbook.address);
    [newBookAddress, newBookStart, newBookEnd, newOracleAddress, newBookIV] = await Controller.getBookInfoByName(newBookID);
    console.log("New Orderbook Address: ", newBookAddress);
    console.log("Round Start: ", newBookStart);
    console.log("Round End: ", newBookEnd);

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

    await expect(Controller.connect(addr1).getQuoteForPosition(badBookID, 130, ethers.utils.parseEther("2.855"))
    ).to.be.revertedWith("Controller: Cannot perform operation on undeployed orderbook!");

    await expect(Controller.connect(addr1).buySwapPosition(badBookID, addr1.address, 130, ethers.utils.parseEther("2.855"))
    ).to.be.revertedWith("Controller: Cannot perform operation on undeployed orderbook!");

    await expect(Controller.connect(addr1).sellSwapPosition(badBookID, addr1.address, 130, ethers.utils.parseEther("0.08"), convertTo64x64(28.5))
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
    await expect(Controller.connect(addr2).buySwapPosition(newBookID, addr1.address, 130, ethers.utils.parseEther("2.855"))
    ).to.be.revertedWith("Controller: Cannot perform operation for another user!");

    await expect(Controller.connect(addr2).sellSwapPosition(newBookID, addr1.address, 130, ethers.utils.parseEther("0.08"), convertTo64x64(28.5))
    ).to.be.revertedWith("Controller: Cannot perform operation for another user!");

    await expect(Controller.connect(addr2).redeemSwapPositions(newBookID, addr1.address)
    ).to.be.revertedWith("Controller: Cannot perform operation for another user!");

    await expect(Controller.connect(addr2).buySwapPosition(newBookID, addr1.address, 130, ethers.utils.parseEther("2.855"))
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
    await expect(Controller.connect(addr1).sellSwapPosition(newBookID, addr1.address, 130, ethers.utils.parseEther("0.08"), convertTo64x64(28.6))
    ).to.be.revertedWith("Controller: User has insufficient funds to collateralize swaps!");
    // Verify that address 1 balance was not affected by reverted transaction
    expect(await Pool.connect(addr1).getUserBalance(addr1.address)).to.equal(ethers.utils.parseEther("2.85"));

    // Attempt to purchase 2.85001 ETH worth of swaps with only 2.85 ETH deposited
    await expect(Controller.connect(addr1).buySwapPosition(newBookID, addr1.address, 130, ethers.utils.parseEther("2.85001"))
    ).to.be.revertedWith("Controller: User has insufficient funds to purchase swaps!");
    // Verify that address 1 balance was not affected by reverted transaction
    expect(await Pool.connect(addr1).getUserBalance(addr1.address)).to.equal(ethers.utils.parseEther("2.85"));
  });

  it("Minting/Selling of variance units should be reflected in the Orderbook", async function () {
    let currOrderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    let askPrice, vaultId, seller;
    let posStrike, posLong, posShort;

    // Sell 28.5 variance units @ 130 strike for 0.08/unit
    //let gasEstimate = await Controller.estimateGas.sellSwapPosition(newBookID, addr1.address, 130, ethers.utils.parseEther("0.08"), convertTo64x64(28.5));
    //console.log('Gas Estimate for sellSwapPosition: ', gasEstimate.toString());
    await Controller.connect(addr1).sellSwapPosition(newBookID, addr1.address, 130, ethers.utils.parseEther("0.08"), convertTo64x64(28.5));
    [askPrice, vaultId, seller] = await currOrderbook.getOrder(0);
    [posStrike, posLong, posShort] = await currOrderbook.getPosition(seller, vaultId);
    console.log("First Order - Ask Price: " + ethers.utils.formatEther(askPrice) + " ETH, VaultId: " + vaultId.toString() + ", Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("0.08"));
    expect(seller).to.equal(addr1.address);
    expect(posStrike).to.equal(130);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(28.5));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(28.5));

    // Sell 36.3 variance units @ 150 strike for 0.05/unit
    await Controller.connect(addr2).sellSwapPosition(newBookID, addr2.address, 150, ethers.utils.parseEther("0.05"), convertTo64x64(36.3));
    [askPrice, vaultId, seller] = await currOrderbook.getOrder(1);
    [posStrike, posLong, posShort] = await currOrderbook.getPosition(seller, vaultId);
    console.log("Second Order - Ask Price: " + ethers.utils.formatEther(askPrice) + " ETH, VaultId: " + vaultId.toString() + ", Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("0.05"));
    expect(seller).to.equal(addr2.address);
    expect(posStrike).to.equal(150);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(36.3));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(36.3));

    // Sell 13.6 variance units @ 125 strike for 0.09/unit
    await Controller.connect(addr2).sellSwapPosition(newBookID, addr2.address, 125, ethers.utils.parseEther("0.09"), convertTo64x64(13.6));
    [askPrice, vaultId, seller] = await currOrderbook.getOrder(0);
    [posStrike, posLong, posShort] = await currOrderbook.getPosition(seller, vaultId);
    console.log("Third Order - Ask Price: " + ethers.utils.formatEther(askPrice) + " ETH, VaultId: " + vaultId.toString() + ", Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("0.09"));
    expect(seller).to.equal(addr2.address);
    expect(posStrike).to.equal(125);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(13.6));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(13.6));

    // Sell 15.4 variance units @ 125 strike for 0.09/unit
    await Controller.connect(addr2).sellSwapPosition(newBookID, addr2.address, 125, ethers.utils.parseEther("0.09"), convertTo64x64(15.4));
    [askPrice, vaultId, seller] = await currOrderbook.getOrder(0);
    [posStrike, posLong, posShort] = await currOrderbook.getPosition(seller, vaultId);
    console.log("Fourth Order - Ask Price: " + ethers.utils.formatEther(askPrice) + " ETH, VaultId: " + vaultId.toString() + ", Address: " + seller);
    console.log("Variance Position - Strike: " + posStrike.toString() + " Long: " + posLong.toString() + "(" + convertFrom64x64(posLong) + ")" + " Short: " + posShort.toString() + "(" + convertFrom64x64(posShort) + ")");
    expect(askPrice).to.equal(ethers.utils.parseEther("0.09"));
    expect(seller).to.equal(addr2.address);
    expect(posStrike).to.equal(125);
    expect(convertFrom64x64(posLong)).to.equal(convertTo8DPString(29));
    expect(convertFrom64x64(posShort)).to.equal(convertTo8DPString(29));
  });

  it("Testing correct order matching for swap purchase quotes and purchase orders", async function () {
    let results;
    console.log("Getting quote for 40 units @ 130 strike");
    results = await Controller.connect(addr3).getQuoteForPosition(newBookID, 130, convertTo64x64(40));
    console.log("Quote Total Price: " + ethers.utils.formatEther(results[0]) + " ETH, " + "(" + convertFrom64x64(results[1]) + ")" + " Units Unfulfilled");
    expect(ethers.utils.formatEther(results[0])).to.equal("2.855");
    expect(convertFrom64x64(results[1])).to.equal("0.00000000");

    // Get quote for 80 variance units @ 130 strike
    console.log("Getting quote for 80 units @ 130 strike");
    results = await Controller.connect(addr3).getQuoteForPosition(newBookID, 130, convertTo64x64(80));
    console.log("Quote Total Price: " + ethers.utils.formatEther(results[0]) + " ETH, " + "(" + convertFrom64x64(results[1]) + ")" + " Units Unfulfilled");
    expect(ethers.utils.formatEther(results[0])).to.equal("4.095");
    expect(convertFrom64x64(results[1])).to.equal("15.20000000");

    // Purchase 2.855 ETH of 130 strike
    // non view function returns a dictionary, need to access value field
    console.log("Purchase 2.855 ETH of 130 strike swap");
    results = await Controller.connect(addr3).buySwapPosition(newBookID, addr3.address, 130, ethers.utils.parseEther("2.855"));
    expect(results.value).to.equal(0); // Expect remaining position to be filled to be zero

    // Get quote for 40 variance units @ 130 strike
    console.log("Getting quote for 40 units @ 130 strike");
    results = await Controller.connect(addr3).getQuoteForPosition(newBookID, 130, convertTo64x64(40));
    console.log("Quote Total Price: " + ethers.utils.formatEther(results[0]) + " ETH, " + "(" + convertFrom64x64(results[1]) + ")" + " Units Unfulfilled");
    expect(ethers.utils.formatEther(results[0])).to.equal("1.24");
    expect(convertFrom64x64(results[1])).to.equal("15.20000000");

    // Test purchase here to verify that the sell function transfers the remainder back to the user if the buy order could not be completely filled.
    // Attempt to purchase 1.30 ETH worth of swaps @ 130 to exceed the quoted supply of 15.2 units for 1.24 ETH.
    console.log("Attempt to purchase 1.30 ETH of swaps @ 130");
    results = await Controller.connect(addr3).buySwapPosition(newBookID, addr3.address, 130, ethers.utils.parseEther("1.30"));
    expect(results.value).to.equal(ethers.utils.parseEther("0.06")); // Expect remaining position to be 0.06 ETH (1.30 ETH - 1.24 ETH)
    let userBalance = Pool.connect(addr3).getUserBalance(addr3.address);
    expect(userBalance).to.equal(ethers.utils.parseEther("0.905")); // Expect remaining funds in our platform to be 0.905 ETH after purchase.
  });

  it("Testing retrieval of user positions", async function () {
    let currOrderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    let addr1Length = await currOrderbook.getNumberOfUserPositions(addr1.address);
    let addr2Length = await currOrderbook.getNumberOfUserPositions(addr2.address);
    let addr3Length = await currOrderbook.getNumberOfUserPositions(addr3.address);

    let userStrike, userLong, userShort;
    console.log("Address 1 has " + addr1Length + " positions");
    expect(Number(addr1Length)).to.equal(1);
    [userStrike, userLong, userShort] = await currOrderbook.getUserPosition(addr1.address, 0);
    console.log("Strike: " + userStrike + " Long: " + convertFrom64x64(userLong) + " Short: " + convertFrom64x64(userShort));
    expect(Number(convertFrom64x64(userLong))).to.equal(0);
    expect(Number(convertFrom64x64(userShort))).to.equal(28.5);

    console.log("Address 2 has " + addr2Length + " positions");
    expect(Number(addr2Length)).to.equal(2);
    [userStrike, userLong, userShort] = await currOrderbook.getUserPosition(addr2.address, 0);
    console.log("Strike: " + userStrike + " Long: " + convertFrom64x64(userLong) + " Short: " + convertFrom64x64(userShort));
    expect(Number(convertFrom64x64(userLong))).to.equal(0);
    expect(Number(convertFrom64x64(userShort))).to.equal(36.3);
    [userStrike, userLong, userShort] = await currOrderbook.getUserPosition(addr2.address, 1);
    console.log("Strike: " + userStrike + " Long: " + convertFrom64x64(userLong) + " Short: " + convertFrom64x64(userShort));
    expect(Number(convertFrom64x64(userLong))).to.equal(29);
    expect(Number(convertFrom64x64(userShort))).to.equal(29);

    console.log("Address 3 has " + addr3Length + " positions");
    expect(Number(addr3Length)).to.equal(2);
    [userStrike, userLong, userShort] = await currOrderbook.getUserPosition(addr3.address, 0);
    console.log("Strike: " + userStrike + " Long: " + convertFrom64x64(userLong) + " Short: " + convertFrom64x64(userShort));
    expect(Number(convertFrom64x64(userLong))).to.equal(28.5);
    expect(Number(convertFrom64x64(userShort))).to.equal(0);
    [userStrike, userLong, userShort] = await currOrderbook.getUserPosition(addr3.address, 1);
    console.log("Strike: " + userStrike + " Long: " + convertFrom64x64(userLong) + " Short: " + convertFrom64x64(userShort));
    expect(Number(convertFrom64x64(userLong))).to.equal(36.3);
    expect(Number(convertFrom64x64(userShort))).to.equal(0);
  });

  it("Testing settlement of swaps @ end of round", async function () {
    //let Orderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    // Note to self: contract methods will not receive a gas estimation if they are reverted
    let currOrderbook = await ethers.getContractAt("Orderbook", newBookAddress, owner);
    await expect(Controller.connect(owner).settleSwapBook(newBookID)
    ).to.be.revertedWith("Controller: Cannot settle swaps before round has ended!");

    console.log("Waiting 30 seconds...");
    sleep(30000);
    totalSettlement = await Controller.connect(owner).settleSwapBook(newBookID);

    let currAddress;
    let numberOfAddresses = await currOrderbook.getNumberOfActiveAddresses();
    console.log("Number of Addresses Returned by Orderbook: ", Number(numberOfAddresses));
    for (i = 0; i < Number(numberOfAddresses); i++) {
      currAddress = await currOrderbook.getAddrByIdx(i);
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
    await expect(Controller.connect(addr2.address).buySwapPosition(newBookID, addr2.address, 130, ethers.utils.parseEther("2.855"))
    ).to.be.revertedWith("Cannot purchase swaps for a round that has ended!");

    await expect(Controller.connect(addr2.address).sellSwapPosition(newBookID, addr2.address, 130, ethers.utils.parseEther("0.08"), convertTo64x64(28.5))
    ).to.be.revertedWith("Cannot sell swaps for a round that has ended!");

    await expect(Controller.connect(owner).settleSwapBook(newBookID)
    ).to.be.revertedWith("Cannot settle swaps for an already settled orderbook!");
  });

  it("Ensure users may redeem positions and withdraw their funds", async function () {
    await expect(Pool.connect(addr1).getUserBalance(addr1.address)
    ).to.equal(ethers.utils.parseEther("0"));
    await expect(Pool.connect(addr2).getUserBalance(addr2.address)
    ).to.equal(ethers.utils.parseEther("3.47"));
    await expect(Pool.connect(addr3).getUserBalance(addr3.address)
    ).to.equal(ethers.utils.parseEther("0.905"));

    await Controller.connect(addr1).redeemSwapPositions(newBookID, addr1.address);
    await Controller.connect(addr2).redeemSwapPositions(newBookID, addr2.address);
    await Controller.connect(addr3).redeemSwapPositions(newBookID, addr3.address);

    await expect(Pool.connect(addr1).getUserBalance(addr1.address)
    ).to.equal(ethers.utils.parseEther("2.28"));
    await expect(Pool.connect(addr2).getUserBalance(addr2.address)
    ).to.equal(ethers.utils.parseEther("10"));
    await expect(Pool.connect(addr3).getUserBalance(addr3.address)
    ).to.equal(ethers.utils.parseEther("1.475"));

    await Pool.connect(addr1.address).withdraw(ethers.utils.formatEther("1"));
    await expect(addr1.getBalance()
    ).to.equal(ethers.utils.parseEther("998.15"));
    await Pool.connect(addr1.address).withdraw(ethers.utils.formatEther("1.28"));
    await expect(addr1.getBalance()
    ).to.equal(ethers.utils.parseEther("999.43"));

    await Pool.connect(addr2.address).withdraw(ethers.utils.formatEther("10"));
    await expect(addr2.getBalance()
    ).to.equal(ethers.utils.parseEther("990"));

    await Pool.connect(addr3.address).withdraw(ethers.utils.formatEther("1.475"));
    await expect(addr3.getBalance()
    ).to.equal(ethers.utils.parseEther("996.475"));
  });
});

