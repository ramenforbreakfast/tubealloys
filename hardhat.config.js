const { task } = require("hardhat/config");
const BigNumber = require("bignumber.js");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-gas-reporter");
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.7.3",
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      hardfork: 'muirGlacier',
      blockGasLimit: 9500000,
      gas: "auto",
      gasPrice: 0,
      chainId: 31337,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      allowUnlimitedContractSize: false,
      accounts: {
        initialIndex: 0,
        count: 5,
        path: "m/44'/60'/0'/0",
        mnemonic: 'test test test test test test test test test test test junc',
        accountsBalance: "10000000000000000000000"
      },
      loggingEnabled: false,
      gasMultiplier: 1
    }
  },
  mocha: {
    // Mocha timeout is for a whole test case, I originally thought this was for asynchronous calls waiting for a promise
    timeout: 30000
  }
};

extendEnvironment(hre => {
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

  hre.convertTo64x64 = convertTo64x64
  hre.convertFrom64x64 = convertFrom64x64
  hre.convertTo8DPString = convertTo8DPString
});
