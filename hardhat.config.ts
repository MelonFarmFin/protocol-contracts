import { HardhatUserConfig } from 'hardhat/config';
import '@nomiclabs/hardhat-ethers';
import '@typechain/hardhat';
import 'hardhat-gas-reporter';
import dotenv from 'dotenv';

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

dotenv.config();

module.exports = {
  defaultNetwork: 'hardhat',
  networks: {
    // use default hardhat network
    hardhat: {
      forking: {
        enabled: true,
        url: 'https://base-sepolia.g.alchemy.com/v2/VQiDmKHs47_v6g_EOXXBZs1OduAs3Hjy',
        blockNumber: 11111000,
      },
    },
  },
  mocha: {
    timeout: 0,
  },
  solidity: {
    compilers: [
      {
        version: '0.8.24',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 1,
    enabled: true,
    token: 'ETH',
    coinmarketcap: process.env.COINMARKETCAP_API,
  },
};
