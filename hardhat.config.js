//const { ethers } = require("hardhat");
//const { task } = require("hardhat/config");

const { task } = require("hardhat/config");

require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.7.3",
};

task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

task("default-provider", "Prints info about the default provider", async () => {
  const provider = await ethers.getDefaultProvider();
  console.log(provider);
});