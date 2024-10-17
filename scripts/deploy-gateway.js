require('dotenv').config();

const { Web3 } = require('web3');
const MelonFarmGateway = require('../artifacts/contracts/MelonFarmGateway.sol/MelonFarmGateway.json');
const { deployContract } = require('./helpers');

const network = 'BaseTestnet';

const configs = {
  BaseTestnet: {
    rpc: 'https://sepolia.base.org',
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
  const MELON_ADDRESS = '0x7ec39BC6263F945D5f07EAe6b0f311AcD8b3416C';
  const WETH_ADDRESS = '0x82d4cF0b68dDCb4589D636212d8d515468E8d161';
  const LP_MELON_ETH_ADDRESS = '0x5586FE39178Efacf0e3389AFB2A2fB108d15f503';
  const FARM_ADDRESS = '0x765ad6db1f32cb465045cef935eb85bcee426473';

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
      FARM_ADDRESS
    ],
  );

  console.log(`... MelonFarmGateway: ${melonFarmGatewayContract}`);
})();
