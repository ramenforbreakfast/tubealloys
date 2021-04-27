const { ethers, upgrades } = require("hardhat");
const BigNumber = require("bignumber.js");

async function main() {
    let Pool;
    let Controller;
    let Oracle;
    let Orderbook;
    let deployReceipt;
    let roundStart, roundEnd;
    let newBookID, newBookAddress, newBookOracle, newBookStart, newBookEnd, newBookIV;

    roundStart = Math.round(Date.now() / 1000);
    roundEnd = Math.round((Date.now() + 86400) / 1000);

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
    Orderbook = await upgrades.deployProxy(orderBookContract, [roundStart, roundEnd, initBookIV, Oracle.address]);
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
    console.log("Book IV: ", newBookIV.toString());
    console.log("Oracle Address: ", newBookOracle);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });