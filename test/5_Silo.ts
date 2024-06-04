import chai, { expect } from 'chai';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { ethers, network } from 'hardhat';
import { solidity } from 'ethereum-waffle';

chai.use(solidity);

describe('Silo', function () {
  async function deployFarm() {
    const signers = await ethers.getSigners();
    for (let i = 0; i < 5; i++) {
      await network.provider.send('hardhat_setBalance', [
        signers[i].address,
        '0x56BC75E2D63100000',
      ]);
    }
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

    const melonEthLPFactory = await ethers.getContractFactory('TestERC20');
    const melonEthLPContract = await melonEthLPFactory.deploy('MelonEthLP', 'MELON-ETH');
    const melonEthLPAddress = melonEthLPContract.address;
    // add pool
    await farmContract.adminAddPool(melonTokenAddress, ethers.utils.parseEther('1')); // MELON poolId = 0
    await farmContract.adminAddPool(melonEthLPAddress, ethers.utils.parseEther('2.5')); // MELON-ETH LP poolId = 1
    // Generate 10 random addresses for experiments.
    const randomAddresses = Array.from({ length: 10 }, () => ethers.Wallet.createRandom().address);

    const ethUsdPrice = await oracleContract.getEthPrice();
    // delta supply should be approximately 0
    let melonEthPrice = ethers.utils.parseUnits('1', 36).div(ethUsdPrice);
    await oracleContract.setAssetPrice(melonEthPrice);

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
        user1: signers[2],
        user2: signers[3],
        user3: signers[4],
      },
      randomAddresses,
      ethUsdPrice,
    };
  }

  describe('#depositFor', function () {
    it('should revert when amount is ZERO', async function () {
      const f = await loadFixture(deployFarm);
      await expect(f.farmContract.siloDeposit(f.randomAddresses[0], 0, 0)).to.be.revertedWith(
        'InvalidAmount',
      );
    });
    it('should revert when not enough allowance for FarmContract', async function () {
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      const allowance = await f.melonTokenContract.allowance(
        f.wallets.admin.address,
        f.farmContractAddress,
      );
      expect(allowance).lt(amount);
      await expect(f.farmContract.siloDeposit(f.randomAddresses[0], 0, amount)).to.be.revertedWith(
        'ERC20: insufficient allowance',
      );
    });
    it('should success deposit MELON and MELON-ETH LP', async function () {
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      let tx = await f.farmContract.siloDeposit(f.randomAddresses[0], 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined;
      await f.melonEthLPContract.mint(f.wallets.admin.address, amount);
      await f.melonEthLPContract.approve(f.farmContractAddress, amount);
      tx = await f.farmContract.siloDeposit(f.randomAddresses[0], 1, amount);
      receipt = await tx.wait();
      event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined;
    });
    it('should mint Deposit NFT when success', async function () {
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      const depositor = f.randomAddresses[0];
      let tx = await f.farmContract.siloDeposit(depositor, 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined;
      const depositId = event?.args?.[1];
      const owner = await f.depositNft.ownerOf(depositId);
      expect(owner).eq(depositor);
    });
    it('should calculate seed correctly when deltaPrice negative', async function () {
      const f = await loadFixture(deployFarm);
      // make deltaPrice negative
      await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.5', 36).div(f.ethUsdPrice));
      const deltaPrice = await f.farmContract.getPriceDelta();
      expect(deltaPrice).lt(0);
      const amount = ethers.utils.parseEther('1');
      const expectedSeed = amount.add(
        amount.mul(deltaPrice.mul(-1)).div(ethers.utils.parseEther('1')),
      );
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      const depositor = f.randomAddresses[0];
      let tx = await f.farmContract.siloDeposit(depositor, 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined; // for tx success
      const seed = event?.args?.[3];
      expect(seed).eq(expectedSeed);
    });
    it('should calculate seed correctly when deltaPrice positive', async function () {
      const f = await loadFixture(deployFarm);
      // make deltaPrice positive
      await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
      const deltaPrice = await f.farmContract.getPriceDelta();
      expect(deltaPrice).gt(0);
      const amount = ethers.utils.parseEther('1');
      const expectedSeed = amount;
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      const depositor = f.randomAddresses[0];
      let tx = await f.farmContract.siloDeposit(depositor, 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined; // for tx success
      const seed = event?.args?.[3];
      expect(seed).eq(expectedSeed);
    });
  });
  describe('#plantSeeds', function () {
    it('should revert when not owner of Deposit NFT', async function () {
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      const depositor = f.randomAddresses[0];
      let tx = await f.farmContract.siloDeposit(depositor, 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined;
      const depositId = event?.args?.[1];
      const owner = await f.depositNft.ownerOf(depositId);
      expect(owner).not.eq(f.wallets.user1.address);
      await expect(
        f.farmContract.connect(f.wallets.user1).siloPlantSeeds(depositId),
      ).to.be.revertedWith('NotDepositOwner');
    });
    it('should update melonGrowth and seeds correctly', async function () {
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      let tx = await f.farmContract.siloDeposit(f.wallets.admin.address, 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined; // for tx success
      const depositId = event?.args?.[1];
      const seeds = event?.args?.[3];
      // create MELON for Silo
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const expectedNewMelonGrowth = await f.farmContract.getGrowthMelons(depositId);
      const expectedCurrentSeed = await f.farmContract.getGrowthSeeds(depositId);
      tx = await f.farmContract.siloPlantSeeds(depositId);
      receipt = await tx.wait();
      event = receipt.events?.find((e) => e.event === 'SiloUpdated');
      expect(event).not.undefined;
      const newMelonGrowth = event?.args?.[1];
      const currentSeed = event?.args?.[2];
      expect(newMelonGrowth).eq(expectedNewMelonGrowth);
      expect(currentSeed).eq(expectedCurrentSeed.add(seeds));
    });
  });
  describe('#withdrawFor', function () {
    it('should revert when not owner of Pod NFT', async function () {
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      let tx = await f.farmContract.siloDeposit(f.wallets.admin.address, 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined; // for tx success
      const depositId = event?.args?.[1];
      const owner = await f.depositNft.ownerOf(depositId);
      expect(owner).not.eq(f.wallets.user1.address);
      await expect(
        f.farmContract.connect(f.wallets.user1).siloWithdraw(f.wallets.user1.address, depositId),
      ).to.be.revertedWith('NotDepositOwner');
    });
    it('should revert when NFT in locking period', async function () {
      const SeasonDepositLocked = 8;
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      let tx = await f.farmContract.siloDeposit(f.wallets.admin.address, 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined; // for tx success
      const depositId = event?.args?.[1];
      const depositSeason = (await f.farmContract.season()).current;
      // skip 3 season
      for (let i = 0; i < 3; i++) {
        await time.increase(60 * 60 + 10);
        await f.farmContract.connect(f.wallets.admin).sunrise();
      }
      const currentSeason = (await f.farmContract.season()).current;
      expect(currentSeason).lt(depositSeason.add(SeasonDepositLocked));
      await expect(
        f.farmContract.siloWithdraw(f.wallets.admin.address, depositId),
      ).to.be.revertedWith('DepositStillLocked');
    });
    it('should withdraw success, claim MELON and deposit asset, burn deposit NFT', async function () {
      const SeasonDepositLocked = 8;
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      await f.melonEthLPContract.mint(f.wallets.admin.address, ethers.utils.parseEther('100'));
      await f.melonEthLPContract.approve(f.farmContractAddress, amount);
      // Deposit MELON-ETH LP
      let tx = await f.farmContract.siloDeposit(f.wallets.admin.address, 1, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined; // for tx success
      const depositId = event?.args?.[1];
      // skip 10 season
      for (let i = 0; i < 10; i++) {
        await time.increase(60 * 60 + 10);
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('1.1', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
      }
      const expectedAssetBalance = (
        await f.melonEthLPContract.balanceOf(f.wallets.admin.address)
      ).add(amount);
      const growthMelon = await f.farmContract.getGrowthMelons(depositId);
      const expectedMelonBalance = (
        await f.melonTokenContract.balanceOf(f.wallets.admin.address)
      ).add(growthMelon);
      tx = await f.farmContract.siloWithdraw(f.wallets.admin.address, depositId);
      receipt = await tx.wait();
      event = receipt.events?.find((e) => e.event === 'SiloWithdrawn');
      expect(event).not.undefined; // for tx success
      const assetBalance = await f.melonEthLPContract.balanceOf(f.wallets.admin.address);
      expect(assetBalance).eq(expectedAssetBalance);
      const melonBalance = await f.melonTokenContract.balanceOf(f.wallets.admin.address);
      expect(melonBalance).eq(expectedMelonBalance);
      await expect(f.depositNft.ownerOf(depositId)).to.be.revertedWith('ERC721: invalid token ID'); // NFT should be burned
    });
  });
  describe('#claimFor', function () {
    it('should revert when not owner of Pod NFT', async function () {
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      let tx = await f.farmContract.siloDeposit(f.wallets.admin.address, 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined; // for tx success
      const depositId = event?.args?.[1];
      const owner = await f.depositNft.ownerOf(depositId);
      expect(owner).not.eq(f.wallets.user1.address);
      await expect(
        f.farmContract.connect(f.wallets.user1).siloClaim(f.wallets.user1.address, depositId),
      ).to.be.revertedWith('NotDepositOwner');
    });
    it('should transfer amount of growthMelon correctly', async function () {
      const f = await loadFixture(deployFarm);
      const amount = ethers.utils.parseEther('1');
      await f.melonTokenContract.approve(f.farmContractAddress, amount);
      let tx = await f.farmContract.siloDeposit(f.wallets.admin.address, 0, amount);
      let receipt = await tx.wait();
      let event = receipt.events?.find((e) => e.event === 'SiloDeposited');
      expect(event).not.undefined; // for tx success
      const depositId = event?.args?.[1];
      // make some growthMelon
      await time.increase(60 * 60 + 10);
      await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('1.1', 36).div(f.ethUsdPrice));
      await f.farmContract.connect(f.wallets.admin).sunrise();
      for (let i = 0; i < 9; i++) {
        await f.farmContract.connect(f.wallets.admin).siloPlantSeeds(depositId);
        await time.increase(60 * 60 + 10);
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('1.1', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
      }
      const expectedGrowMelon = await f.farmContract.getGrowthMelons(depositId);
      const balanceBefore = await f.melonTokenContract.balanceOf(f.wallets.admin.address);
      await f.farmContract.siloClaim(f.wallets.admin.address, depositId);
      const balanceAfter = await f.melonTokenContract.balanceOf(f.wallets.admin.address);
      expect(balanceAfter).eq(balanceBefore.add(expectedGrowMelon));
    });
  });
});
