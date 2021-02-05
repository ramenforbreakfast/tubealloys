const { expect } = require("chai");

let Orderbook;
let owner;
let testDate;
let addr1;
let addr2;
let addr3;
let addr4;

beforeEach(async function() {
    [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    testDate = new Date('2021.02.10').getTime() / 1000;

    const Contract = await ethers.getContractFactory("Orderbook");

    Orderbook = await Contract.deploy(testDate);
    await Orderbook.deployed();
});

describe("Deployment", function () {
    it("Right owner", async function () {
        expect(await Orderbook.owner()).to.equal(owner.address);
    });

    it("Right epoch", async function () {
        expect(await Orderbook.contractEpoch()).to.equal(testDate);
    });
});

describe("Opening Orders", function () {
    it("Add Sell Order and Check Position", async function () {
        await Orderbook.sellOrder(addr1.address, 10, 5, 100);
        let position, order;
        position = await Orderbook.getPosition(addr1.address, 0);
        expect(position[0]).to.equal(10);
        expect(position[1]).to.equal(100);
        expect(position[2]).to.equal(100);
        order = await Orderbook.getOrder(0);
        expect(order[0]).to.equal(5);
        expect(order[1]).to.equal(0);
        expect(order[2]).to.equal(addr1.address);
    });
});