import * as dotenv from 'dotenv';

import { HardhatUserConfig, task } from 'hardhat/config';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-ethers';
// import "@nomiclabs/hardhat-waffle";
import '@typechain/hardhat';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import 'hardhat-abi-exporter';
import '@openzeppelin/hardhat-upgrades';

dotenv.config();

task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

const config: HardhatUserConfig = {
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
  networks: {
    hardhat: {
      forking: {
        enabled: true,
        url: 'https://base-pokt.nodies.app',
        blockNumber: 14412469,
      },
    },
    bsc_testnet: {
      url: process.env.BSC_TEST_NET_RPC,
      accounts: [process.env.PRIVATE_KEY!],
    },
    arbitrum_testnet: {
      url: process.env.ARBITRUM_TEST_NET_RPC,
      accounts: [process.env.PRIVATE_KEY!],
    },
    viction_testnet: {
      url: process.env.VICTION_TEST_NET_RPC,
      accounts: [process.env.PRIVATE_KEY!],
    },
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 1,
    enabled: true,
    token: 'ETH',
    coinmarketcap: process.env.COINMARKETCAP_API,
  },
  etherscan: {
    apiKey: process.env.EXPLORER_API_KEY,
    customChains: [
      {
        network: 'bsc_testnet',
        chainId: 97,
        urls: {
          apiURL: 'https://api-testnet.bscscan.com/api',
          browserURL: 'https://testnet.bscscan.com/',
        },
      },
      {
        network: 'arbitrum_testnet',
        chainId: 421614,
        urls: {
          apiURL: 'https://api-sepolia.arbiscan.io/api',
          browserURL: 'https://sepolia.arbiscan.io/',
        },
      },
      {
        network: 'viction_testnet',
        chainId: 89,
        urls: {
          apiURL: 'https://scan-api-testnet.viction.xyz/api/contract/hardhat/verify',
          browserURL: 'https://testnet.vicscan.xyz',
        },
      },
    ],
  },
  abiExporter: {
    runOnCompile: true,
    flat: true,
    except: ['IERC20'],
  },
};

export default config;
