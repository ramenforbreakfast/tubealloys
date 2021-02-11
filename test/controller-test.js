const { expect } = require("chai");
const { ethers } = require("hardhat");

let Controller;
let Oracle;
let roundEnd;
let owner, addr1, addr2, addr3, addr4;

beforeEach(async function () {
    [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    //let date = new Date('2021.04.10');
    roundEnd = Math.round(new Date('2021.04.10').getTime() / 1000);

    const controllerContract = await ethers.getContractFactory("Controller");
    Controller = await controllerContract.deploy();
    await Controller.deployed();

    const oracleContract = await ethers.getContractFactory("Oracle");
    Oracle = await oracleContract.deploy();
    await Oracle.deployed();
});


describe("Test Orderbook Creation", function () {
    it("New Orderbook Should Return Correct Initialized Values", async function () {
        let roundStart = Math.round(Date.now() / 1000);
        console.log("Round Start: ", roundStart);
        console.log("Round End: ", roundEnd);
        console.log("Controller Address: ", Controller.address);
        console.log("Oracle Address: ", Oracle.address);
        await Controller.createNewSwapBook(Oracle.address, roundStart, roundEnd);
        let newBookAddress, newBookStart, newBookEnd;
        [newBookAddress, newBookStart, newBookEnd] = await Controller.getBookInfoByIndex(0);
        expect(newBookAddress).to.equal(Oracle.address);
        expect(roundStart).to.equal(roundStart);
        expect(roundEnd).to.equal(roundEnd);
        // Below does not work because JS numbers are 64 bit FP versus uint256 from solidity in this case
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
        //expect(await Controller.getBookInfoByIndex(0)).to.equal([Oracle.address, roundStart, roundEnd]);
    });
});

