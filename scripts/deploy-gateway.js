require('dotenv').config();

const { Web3 } = require('web3');
const MelonFarmGateway = require('../artifacts/contracts/MelonFarmGateway.sol/MelonFarmGateway.json');
const { deployContract } = require('./helpers');

const network = 'BaseTestnet';

const configs = {
  BaseTestnet: {
    rpc: 'https://base-sepolia.g.alchemy.com/v2/VQiDmKHs47_v6g_EOXXBZs1OduAs3Hjy',
    deployerKey: process.env.DEPLOYER_KEY,
  },
};

(async function () {
  const config = configs[network];

  if (!config) {
    console.error(`!network:${network}`);
    process.exit(1);
  }

  const web3 = new Web3(config.rpc);

  console.log('');
  console.log(`... Deploy on network ${network} ...`);

  const PANCAKE_V2_ROUTER_BASE = '0x8cFe327CEc66d1C090Dd72bd0FF11d690C33a2Eb';
  const MELON_ADDRESS = '0xBef5C3A9287EEa83a9B397c132c3acD04c3A880F';
  const WETH_ADDRESS = '0x4200000000000000000000000000000000000006';
  const LP_MELON_ETH_ADDRESS = '0x011902b76fa2c55a5D1216e162D3915AB8662822';
  const FARM_ADDRESS = '0x9325b44b9bd7dfe210654d9ea0064198bcfb7ae8';
  const SILO_ASSET_ADDRESS = '0xd121a603ce76A6065245283eDF7883b29F3Ab955';
  const POD_ASSET_ADDRESS = '0x95350daa95C230a8BB9764450899931Cc3513d1C';

  const melonFarmGatewayContract = await deployContract(
    'MelonFarmGateway Contract',
    web3,
    config.deployerKey,
    MelonFarmGateway.abi,
    MelonFarmGateway.bytecode,
    [
      PANCAKE_V2_ROUTER_BASE,
      WETH_ADDRESS,
      MELON_ADDRESS,
      LP_MELON_ETH_ADDRESS,
      FARM_ADDRESS,
      SILO_ASSET_ADDRESS,
      POD_ASSET_ADDRESS
    ],
  );

  console.log(`... MelonFarmGateway: ${melonFarmGatewayContract}`);
})();
