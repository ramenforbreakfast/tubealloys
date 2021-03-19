const hre = require("hardhat");
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

async function main() {
    const ABDKTest = await hre.ethers.getContractFactory("ABDKtest");
    const testContract = await ABDKTest.deploy();
    await testContract.deployed();
    console.log("ABDK contract deployed to: ", testContract.address);

    console.log("Call mul on 1.28 * 1.56 = ", convertFrom64x64(await testContract.mul(convertTo64x64(1.28), convertTo64x64(1.56))));
    console.log("Call div on 19.28 / 1.56 = ", convertFrom64x64(await testContract.div(convertTo64x64(19.28), convertTo64x64(1.56))));
    console.log("Call mulu on 1.786 * 6 = ", (await testContract.mulu(convertTo64x64(1.786), 6)).toString());
    console.log("Call divu on 19/5 = ", convertFrom64x64(await testContract.divu(19, 5)));
    console.log("Call mul on 0.5 * 0.78 = ", convertFrom64x64(await testContract.mul(convertTo64x64(0.5), convertTo64x64(0.78))));
    console.log("Call div on 0.85 / 1.56 = ", convertFrom64x64(await testContract.div(convertTo64x64(0.85), convertTo64x64(1.56))));
    console.log("Call mulu on 0.19583 * 3 = ", (await testContract.mulu(convertTo64x64(0.19583), 3)).toString());
    console.log("Call divu on 5/19 = ", convertFrom64x64(await testContract.divu(5, 19)));
    console.log("Call mulu on 24.8 * 0.05 eth in wei = ", (await testContract.mulu(convertTo64x64(24.8), hre.ethers.utils.parseEther("0.05"))).toString());
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });