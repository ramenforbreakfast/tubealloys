require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("hardhat-gas-reporter");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
  solidity: "0.7.3",
  gasReporter: {
    currency: 'USD',
    coinmarketcap: '8a99babd-7e02-4071-a2f1-77a0d4f6532f',
    enabled: true
  }
};