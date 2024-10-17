import chai, { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ethers } from 'hardhat';
import { solidity } from 'ethereum-waffle';

chai.use(solidity);

describe('Farm', function () {
  async function deployFarm() {
    const signers = await ethers.getSigners();
    const factory = await ethers.getContractFactory('Farm');
    const admin = signers[0];
    const treasury = signers[1];
    const farmContract = await factory.deploy('BaseTestnet', admin.address, treasury.address);
    const farmContractAddress = farmContract.address;
    const melonTokenAddress = await farmContract.melon();
    const melonTokenContract = await ethers.getContractAt('Melon', melonTokenAddress);
    const oracleContract = await ethers.getContractAt('MockOracle', await farmContract.oracle());
    const depositNft = await ethers.getContractAt('MelonAsset', (await farmContract.silo()).asset);
    const podNft = await ethers.getContractAt('MelonAsset', (await farmContract.field()).asset);

    const melonEthLPFactory = await ethers.getContractFactory('ERC20');
    const melonEthLPContract = await melonEthLPFactory.deploy('MelonEthLP', 'MELON-ETH');
    const melonEthLPAddress = melonEthLPContract.address;
    // Generate 10 random addresses for experiments.
    const randomAddresses = Array.from({ length: 10 }, () => ethers.Wallet.createRandom().address);

    return {
      farmContract,
      farmContractAddress,
      melonTokenContract,
      melonTokenAddress,
      oracleContract,
      depositNft,
      podNft,
      melonEthLPContract,
      melonEthLPAddress,
      wallets: {
        admin: signers[0],
        treasury: signers[1],
      },
      randomAddresses,
    };
  }

  describe('#constructor', function () {
    it('should deploy correctly', async function () {
      const f = await loadFixture(deployFarm);
      const owner = await f.farmContract.admin();
      // admin is the admin address
      expect(owner).equal(f.wallets.admin.address);
      // treasury is the treasury address
      expect(await f.farmContract.treasury()).equal(f.wallets.treasury.address);

      // check MELON address and mint amount
      expect(f.melonTokenAddress).not.equal('0x0000000000000000000000000000000000000000');
      expect(await f.melonTokenContract.totalSupply()).equal(ethers.utils.parseEther('1000'));
      expect(await f.melonTokenContract.balanceOf(f.wallets.admin.address)).equal(
        ethers.utils.parseEther('1000'),
      );

      // check MELON-ETH pair created
      const uniswapFactory = await ethers.getContractAt(
        'IUniswapV2Factory',
        '0x02a84c1b3BBD7401a5f7fa98a384EBC70bB5749E',
      );
      const pairAddress = await uniswapFactory.getPair(
        f.melonTokenAddress,
        '0x4200000000000000000000000000000000000006',
      );
      // pair created
      expect(pairAddress).not.equal('0x0000000000000000000000000000000000000000');

      // check deploy MelonAsset
      expect(f.depositNft.address).not.equal('0x0000000000000000000000000000000000000000');
      expect(f.podNft.address).not.equal('0x0000000000000000000000000000000000000000');
      // check deploy Oracle
      expect(f.oracleContract.address).not.equal('0x0000000000000000000000000000000000000000');
    });
  });
});
