import chai, { expect } from 'chai';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { ethers, network } from 'hardhat';
import { solidity } from 'ethereum-waffle';

chai.use(solidity);

describe('Weather', function () {
  async function deployFarm() {
    const signers = await ethers.getSigners();
    await network.provider.send('hardhat_setBalance', [signers[0].address, '0x56BC75E2D63100000']);
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
    // add pool
    await farmContract.adminAddPool(melonTokenAddress, ethers.utils.parseEther('1'));
    await farmContract.adminAddPool(melonEthLPAddress, ethers.utils.parseEther('2.5'));
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

  describe('#getDeltaSupply', function () {
    it('should getDeltaSupply correctly', async function () {
      const f = await loadFixture(deployFarm);
      // CURRENT TOTAL SUPPLY: 1000
      const melonTotalSupply = await f.melonTokenContract.totalSupply();
      const ethUsdPrice = await f.oracleContract.getEthPrice();
      // delta supply should be approximately 0
      let melonEthPrice = ethers.utils.parseUnits('1', 36).div(ethUsdPrice);
      await f.oracleContract.setAssetPrice(melonEthPrice);
      let deltaSupply = await f.farmContract.getSupplyDelta();
      expect(deltaSupply)
        .lte(ethers.utils.parseEther('0.000001'))
        .gte(-ethers.utils.parseEther('0.000001'));
      // delta supply should be correctly when 1MELON = 1.25$
      melonEthPrice = ethers.utils.parseUnits('1.25', 36).div(ethUsdPrice);
      await f.oracleContract.setAssetPrice(melonEthPrice);
      deltaSupply = await f.farmContract.getSupplyDelta();
      let absExpectedSupply = melonTotalSupply
        .mul(ethers.utils.parseUnits('0.25', 18))
        .div(ethers.utils.parseUnits('1.25', 18));
      expect(deltaSupply)
        .lte(absExpectedSupply.add(ethers.utils.parseEther('0.000001')))
        .gt(absExpectedSupply.sub(ethers.utils.parseEther('0.000001')));
      // delta supply should be correctly when 1MELON = 0.8$
      melonEthPrice = ethers.utils.parseUnits('0.8', 36).div(ethUsdPrice);
      await f.oracleContract.setAssetPrice(melonEthPrice);
      deltaSupply = await f.farmContract.getSupplyDelta();
      absExpectedSupply = melonTotalSupply
        .mul(ethers.utils.parseUnits('0.2', 18))
        .div(ethers.utils.parseUnits('0.8', 18));
      expect(deltaSupply)
        .gt(absExpectedSupply.add(ethers.utils.parseEther('0.000001')).mul(-1))
        .lt(absExpectedSupply.sub(ethers.utils.parseEther('0.000001')).mul(-1));
    });
  });

  describe('#getPriceDelta', function () {
    it('should getPriceDelta correctly', async function () {
      const f = await loadFixture(deployFarm);
      const ethUsdPrice = await f.oracleContract.getEthPrice();
      // delta price should be approximately 0
      let melonEthPrice = ethers.utils.parseUnits('1', 36).div(ethUsdPrice);
      await f.oracleContract.setAssetPrice(melonEthPrice);
      let deltaPrice = await f.farmContract.getPriceDelta();
      expect(deltaPrice)
        .lte(ethers.utils.parseEther('0.00001'))
        .gt(-ethers.utils.parseEther('0.00001'));

      // delta price should be approximately 0.25
      melonEthPrice = ethers.utils.parseUnits('1.25', 36).div(ethUsdPrice);
      await f.oracleContract.setAssetPrice(melonEthPrice);
      deltaPrice = await f.farmContract.getPriceDelta();
      expect(deltaPrice).lte(ethers.utils.parseEther('0.25')).gt(ethers.utils.parseEther('0.2499'));

      // delta price should be approximately -0.2
      melonEthPrice = ethers.utils.parseUnits('0.8', 36).div(ethUsdPrice);
      await f.oracleContract.setAssetPrice(melonEthPrice);
      deltaPrice = await f.farmContract.getPriceDelta();
      expect(deltaPrice)
        .lte(ethers.utils.parseEther('-0.2'))
        .gt(ethers.utils.parseEther('-0.2001'));
    });
  });
  describe('#getGrowthSeeds', function () {
    it('should getGrowthSeeds correctly', async function () {
      const f = await loadFixture(deployFarm);
      const ethUsdPrice = await f.oracleContract.getEthPrice();
      await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('1', 36).div(ethUsdPrice));
      await f.melonTokenContract
        .connect(f.wallets.admin)
        .approve(f.farmContractAddress, ethers.utils.parseEther('1000'));
      await f.farmContract
        .connect(f.wallets.admin)
        .siloDeposit(f.wallets.admin.address, 0, ethers.utils.parseEther('1000'));
      // after 8 season
      for (let i = 0; i < 8; i++) {
        await time.increase(3610);
        await f.farmContract.connect(f.wallets.admin).sunrise();
      }
      //growthSeed ~ 1.00762195% * 1000 = 10,00762195 MELON
      let growthSeeds = await f.farmContract.getGrowthSeeds(0);
      let expectedSupply = ethers.utils.parseEther('10.00762195');
      expect(growthSeeds)
        .lte(expectedSupply.add(ethers.utils.parseEther('0.00000001')))
        .gt(expectedSupply.sub(ethers.utils.parseEther('0.00000001')));

      // after 55 season
      for (let i = 0; i < 47; i++) {
        await time.increase(3610);
        await f.farmContract.connect(f.wallets.admin).sunrise();
      }
      //growthSeed ~ 1.00524009% * 1000 = 10.0524009 MELON
      growthSeeds = await f.farmContract.getGrowthSeeds(0);
      expectedSupply = ethers.utils.parseEther('10.0524009');
      expect(growthSeeds)
        .lte(expectedSupply.add(ethers.utils.parseEther('0.0000001')))
        .gt(expectedSupply.sub(ethers.utils.parseEther('0.0000001')));
    });
  });
});
