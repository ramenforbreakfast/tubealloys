//const { ethers } = require("hardhat");
//const { task } = require("hardhat/config");

const { task } = require("hardhat/config");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-waffle");
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

task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();
  let balance;
  for (const account of accounts) {
    console.log(account.address);
    balance = await account.getBalance()
    console.log(balance.toString());
  }
});

task("default-provider", "Prints info about the default provider", async () => {
  const provider = await ethers.getDefaultProvider();
  console.log(provider);
});