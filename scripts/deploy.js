require('dotenv').config();

const { Web3 } = require('web3');
const FarmBuild = require('../artifacts/contracts/6_Farm.sol/Farm.json');
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
  const deployerAddress = web3.eth.accounts.privateKeyToAccount(config.deployerKey).address;
  // FIXME: save startTime for contract verification
  const startTime = Math.round(new Date().getTime() / 1000);
  console.log(startTime);

  console.log('');
  console.log(`... Deploy on network ${network} ...`);

  const farmContract = await deployContract(
    'Farm Contract',
    web3,
    config.deployerKey,
    FarmBuild.abi,
    FarmBuild.bytecode,
    [
      network,
      deployerAddress, // admin
      deployerAddress, // treasury
      startTime
    ],
  );

  console.log(`... Farm: ${farmContract}`);
})();
