const { expect, util } = require("chai");
const { ethers } = require("hardhat");
const BigNumber = require('bignumber.js');

let Orderbook;
let owner;
let addr1;
let addr2;
let addr3;
let addr4;
let addr5;
let addr6;

BigNumber.set({DECIMAL_PLACES: 16});

function convertTo64x64(val) {
    two = BigNumber("2").pow(64);
    valBN = BigNumber(val);
    one = BigNumber("1");
    valBN = valBN.times(two);

    if(!valBN.toFixed().includes(".")) {
        return ethers.BigNumber.from(valBN.toFixed());
    }

    return ethers.BigNumber.from(valBN.plus(one).toFixed().split(".")[0]);
}

function convertFrom64x64(val) {
    two = ethers.BigNumber.from("2").pow(64);
    ten = ethers.BigNumber.from("10").pow(16);
    bigVal = val.mul(ten).div(two).toString();
    if(bigVal.length <= 16) {
        return parseFloat("0." + bigVal.padStart(16, "0")).toFixed(8).toString();
    }
    return bigVal.slice(0, bigVal.length - 16) + "." + parseFloat("0." + bigVal.slice(bigVal.length - 16, bigVal.length)).toFixed(8).toString().replace("0.","");
}

function getRandomInt(max) {
    i = Math.floor(Math.random() * Math.floor(max));
    if(i == 0) {
        return 1;
    }
    return i;
  }

function getRandomFloat(max) {
    return getRandomInt(max).toString() + "." + getRandomInt(max).toString();
}

function makeSellStruct(addr) {
    return {
        'address': addr,
        'strike':  getRandomInt(100),
        'askPrice': ethers.utils.parseEther(getRandomInt(10).toString()),
        'sellAmount': convertTo64x64(getRandomFloat(100000))
    };
}

function makeBuyStruct(addr, maxStrike, maxAmount) {
    return {
        'address': addr,
        'strike':  getRandomInt(maxStrike),
        'maxAmount': maxAmount
    };
}

beforeEach(async function() {
    [owner, addr1, addr2, addr3, addr4, addr5, addr6] = await ethers.getSigners();
    startDate = new Date('2021.04.03').getTime() / 1000;
    endDate = new Date('2021.04.10').getTime() / 1000;
    roundIV = 10;

    const Contract = await ethers.getContractFactory("Orderbook");

    Orderbook = await Contract.deploy(startDate, endDate, roundIV);
    await Orderbook.deployed();
});

describe("Deployment", function () {
    it("Right owner", async function () {
        expect(await Orderbook.owner()).to.equal(owner.address);
    });

    it("Right epoch", async function () {
        expect(await Orderbook.roundEnd()).to.equal(endDate);
    });
});

describe("Opening Orders", function () {
    it("Add sell orders and check positions", async function () {
        let sellers, position, addresses, i;
        addresses = [addr1, addr2, addr3, addr4, addr5, addr6];
        for(i = 0; i < addresses.length; i++) {
            sellers = makeSellStruct(addresses[i].address);
            await Orderbook.sellOrder(sellers.address, sellers.strike, sellers.askPrice, sellers.sellAmount);
            position = await Orderbook.getPosition(sellers.address, 0);
            expect(position[0]).to.equal(sellers.strike);
            expect(position[1]).to.equal(sellers.sellAmount);
            expect(position[2]).to.equal(sellers.sellAmount);
        }
    });
});

describe("Filling Orders", function () {
    it("Add Sell Orders, fill some and check bought amount is equal to sold amount", async function () {
        let buyOrder, filledOrder, sellers, position, addresses;
        let i, i2, ct, maxStrike, totalBought, totalSold, plen;
        let totalPaid, totalSpent, gwei;
        addresses = [addr1, addr2, addr3, addr4, addr5, addr6];
        sellers = [];
        maxStrike = 0;
        totalBought = 0;
        totalSold = 0;
        totalSpent = ethers.BigNumber.from(0);
        totalPaid = ethers.BigNumber.from(0);
        ct = 0;
        gwei = ethers.BigNumber.from("1000000000");
        
        for(i = 0; i < Math.floor(addresses.length / 2); i++) {
            sellers.push(makeSellStruct(addresses[i].address));
            if(sellers[i].strike > maxStrike) {
                maxStrike = sellers[i].strike;
            }
            await Orderbook.sellOrder(sellers[i].address, sellers[i].strike, sellers[i].askPrice, sellers[i].sellAmount);
        }

        for(i = Math.floor(addresses.length / 2); i < addresses.length; i++) {
            buyer = makeBuyStruct(addresses[i].address, maxStrike, sellers[ct].sellAmount);
            buyOrder = await Orderbook.getBuyOrderbyUnitAmount(buyer.strike, buyer.maxAmount);
            await Orderbook.fillBuyOrderbyMaxPrice(buyer.address, buyer.strike, buyOrder[0]);
            plen = await Orderbook.getNumberofUserPositions(buyer.address);
            totalSpent = totalSpent.add(buyOrder[0]);
            for(i2 = 0; i2 < plen; i2++) {
                position = await Orderbook.getPosition(buyer.address, i2);
                totalBought += parseFloat(convertFrom64x64(position[1]));
            }
            ct++;
        }
        
        for(i = 0; i < Math.floor(addresses.length / 2); i++) {
            position = await Orderbook.getPosition(sellers[i].address, 0);
            totalSold += parseFloat(convertFrom64x64(position[2])) - parseFloat(convertFrom64x64(position[1]));
            filledOrder = await Orderbook.displayFilledOrderPayout(sellers[i].address);
            totalPaid = totalPaid.add(filledOrder);
        }

        expect(totalPaid.div(gwei).toString()).to.be.oneOf([totalSpent.div(gwei).toString(), totalSpent.div(gwei).add(1).toString(), totalSpent.div(gwei).sub(1).toString()]);

        expect(totalSold).to.be.within(totalBought - 1, totalBought + 1);
    });
});