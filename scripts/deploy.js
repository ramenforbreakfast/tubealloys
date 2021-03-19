const { ethers, upgrades } = require("hardhat");
const BigNumber = require("bignumber.js");

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

async function main() {
    let Pool;
    let Controller;
    let Oracle;
    let Orderbook;
    let deployReceipt;
    let roundStart, roundEnd;
    let newBookID, newBookAddress, newBookOracle, newBookStart, newBookEnd, newBookIV;

    roundStart = Math.round(Date.now() / 1000);
    roundEnd = Math.round((Date.now() + 45000) / 1000);

    const poolContract = await ethers.getContractFactory("Pool");
    console.log("Deploying Pool...");
    Pool = await upgrades.deployProxy(poolContract);
    await Pool.deployed();
    console.log("Pool deployed to: ", Pool.address);

    try {
        deployReceipt = await Pool.deployTransaction.wait();
    } catch (e) {
        console.log(`Transaction Receipt Not Received!\n${e}`);
    }
    console.log("Gas spent to deploy:\n" + deployReceipt.cumulativeGasUsed.toString() + " wei");

    let poolOwner = await Pool.owner();
    console.log("Pool is owned by: ", poolOwner);

    const controllerContract = await ethers.getContractFactory("Controller");
    console.log("Deploying Controller...")
    Controller = await upgrades.deployProxy(controllerContract, [Pool.address]);
    await Controller.deployed();
    console.log("Controller deployed to: ", Controller.address);
    try {
        deployReceipt = await Controller.deployTransaction.wait();
    } catch (e) {
        console.log(`Transaction Receipt Not Received!\n${e}`);
    }
    console.log("Gas spent to deploy:\n" + deployReceipt.cumulativeGasUsed.toString() + " wei");
    await Pool.transferOwnership(Controller.address);

    const oracleContract = await ethers.getContractFactory("Oracle");
    Oracle = await oracleContract.deploy();
    await Oracle.deployed();
    try {
        deployReceipt = await Oracle.deployTransaction.wait();
    } catch (e) {
        console.log(`Transaction Receipt Not Received!\n${e}`);
    }
    console.log("Gas spent to deploy:\n" + deployReceipt.cumulativeGasUsed.toString() + " wei");
    console.log("Oracle deployed to: ", Oracle.address);

    const orderBookContract = await ethers.getContractFactory("Orderbook");
    let initBookIV = await Oracle.getLatestImpliedVariance();
    newBookID = "ETH-" + initBookIV + "-" + roundStart + "-" + roundEnd;
    console.log("New Book Name: ", newBookID);
    Orderbook = await upgrades.deployProxy(orderBookContract, [roundStart, roundEnd, Oracle.address, initBookIV]);
    await Orderbook.deployed();
    try {
        deployReceipt = await Orderbook.deployTransaction.wait();
    } catch (e) {
        console.log(`Transaction Receipt Not Received!\n${e}`);
    }
    console.log("Gas spent to deploy:\n" + deployReceipt.cumulativeGasUsed.toString() + " wei");
    console.log("Orderbook deployed to: ", Orderbook.address);
    await Orderbook.transferOwnership(Controller.address);

    await Controller.addNewSwapBook(newBookID, Orderbook.address);
    [newBookAddress, newBookStart, newBookEnd, newBookOracle, newBookIV] = await Controller.getBookInfoByName(newBookID);
    console.log("Round Start: ", newBookStart.toString());
    console.log("Round End: ", newBookEnd.toString());
    console.log("Oracle Address: ", newBookOracle);
    console.log("Book IV: ", newBookIV.toString());
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });