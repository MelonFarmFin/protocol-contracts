import chai, { expect } from 'chai';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { ethers, network } from 'hardhat';
import { solidity } from 'ethereum-waffle';

chai.use(solidity);

describe('Sun', function () {
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

    const melonEthLPFactory = await ethers.getContractFactory('ERC20');
    const melonEthLPContract = await melonEthLPFactory.deploy('MelonEthLP', 'MELON-ETH');
    const melonEthLPAddress = melonEthLPContract.address;
    // add pool
    await farmContract.adminAddPool(melonTokenAddress, ethers.utils.parseEther('1'));
    await farmContract.adminAddPool(melonEthLPAddress, ethers.utils.parseEther('2.5'));
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

  describe('#doSunrise', function () {
    it('should be call by anyone', async function () {
      const f = await loadFixture(deployFarm);
      expect(await f.farmContract.connect(f.wallets.admin).sunrise()).to.emit(
        f.farmContract,
        'Sunrise',
      );
      await time.increase(60 * 60 + 10);
      expect(await f.farmContract.connect(f.wallets.treasury).sunrise()).to.emit(
        f.farmContract,
        'Sunrise',
      );
    });
    it('should revert when season not end', async function () {
      const f = await loadFixture(deployFarm);
      expect(await f.farmContract.connect(f.wallets.admin).sunrise()).to.emit(
        f.farmContract,
        'Sunrise',
      );
      await time.increase(30 * 60);
      await expect(f.farmContract.connect(f.wallets.treasury).sunrise()).to.be.reverted;
    });
    it('should reward the caller correctly', async function () {
      const f = await loadFixture(deployFarm);
      await f.farmContract.connect(f.wallets.admin).sunrise();
      await time.increase(60 * 60 + 10);
      // deltaSupply < 0 => mint for caller 1 MELON
      await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
      let deltaSupply = await f.farmContract.getSupplyDelta();
      expect(deltaSupply).to.be.lt(0);
      await f.farmContract.connect(f.wallets.user1).sunrise();
      let userBalance = await f.melonTokenContract.balanceOf(f.wallets.user1.address);
      expect(userBalance).to.be.eq(ethers.utils.parseEther('1'));
      // deltaSupply > 0 (not too big) => mint for caller 0.681% deltaSupply
      await time.increase(60 * 60 + 10);
      await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('1.25', 36).div(f.ethUsdPrice));
      deltaSupply = await f.farmContract.getSupplyDelta();
      expect(deltaSupply).to.be.gt(0);
      await f.farmContract.connect(f.wallets.user2).sunrise();
      userBalance = await f.melonTokenContract.balanceOf(f.wallets.user2.address);
      let expectedBalance = deltaSupply.mul(618).div(100000);
      expect(userBalance).to.be.equal(expectedBalance);
      // deltaSupply too big => mint for caller 10 MELON
      await time.increase(60 * 60 + 10);
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('100', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('100', 36).div(f.ethUsdPrice));
      deltaSupply = await f.farmContract.getSupplyDelta();
      expect(deltaSupply).to.be.gt(0);
      await f.farmContract.connect(f.wallets.user3).sunrise();
      userBalance = await f.melonTokenContract.balanceOf(f.wallets.user3.address);
      expectedBalance = ethers.utils.parseEther('10');
      expect(userBalance).to.be.equal(expectedBalance);
    });
  });

  describe('#growSupply', function () {
    it('should not be call when deltaSupply negative', async function () {
      const f = await loadFixture(deployFarm);
      await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
      let deltaSupply = await f.farmContract.getSupplyDelta();
      expect(deltaSupply).to.be.lt(0);
      let tx = await f.farmContract.connect(f.wallets.admin).sunrise();
      let receipt = await tx.wait();
      let growSupplyEvent = receipt.events?.find((e) => e.event === 'SupplyMinted');
      expect(growSupplyEvent).to.be.undefined;
    });
    it('should transfer for treasury correctly', async function () {
      const f = await loadFixture(deployFarm);
      const treasuryBalanceBefore = await f.melonTokenContract.balanceOf(
        f.wallets.treasury.address,
      );
      await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
      let deltaSupply = await f.farmContract.getSupplyDelta();
      let newMelon = deltaSupply.mul(618).div(1000);
      let melonForTreasury = newMelon.mul(100).div(1000);
      await f.farmContract.connect(f.wallets.admin).sunrise();
      let treasuryBalanceAfter = await f.melonTokenContract.balanceOf(f.wallets.treasury.address);
      expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(melonForTreasury);
    });

    describe('Calculate Melon for Silo and Pod', function () {
      it('should calculate Melon for Silo and Pod correctly (when no Pod)', async function () {
        const f = await loadFixture(deployFarm);
        let fieldInfo = await f.farmContract.field();
        expect(fieldInfo.podRedeemed).equal(fieldInfo.podLine);
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
        let deltaSupply = await f.farmContract.getSupplyDelta();
        let newMelon = deltaSupply.mul(618).div(1000);
        let melonForTreasury = newMelon.mul(100).div(1000);
        let tx = await f.farmContract.connect(f.wallets.admin).sunrise();
        let receipt = await tx.wait();
        let growSupplyEvent = receipt.events?.find((e) => e.event === 'SupplyMinted');
        expect(growSupplyEvent).to.not.be.undefined;
        expect(growSupplyEvent?.args?.[1]).to.be.equal(newMelon.sub(melonForTreasury));
      });
      it('should calculate Melon for Silo and Pod correctly (when PodLine is small)', async function () {
        const f = await loadFixture(deployFarm);
        // make field has some available soil
        for (let i = 0; i < 10; i++) {
          await time.increase(60 * 60 + 10);
          await f.oracleContract.setAssetPrice(
            ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice),
          );
          await f.farmContract.connect(f.wallets.admin).sunrise();
        }
        await f.melonTokenContract
          .connect(f.wallets.admin)
          .approve(f.farmContractAddress, ethers.utils.parseEther('1000'));
        await f.farmContract
          .connect(f.wallets.admin)
          .fieldPurchasePod(f.wallets.admin.address, ethers.utils.parseEther('10'));
        let fieldInfo = await f.farmContract.field();
        const expectedForPod = fieldInfo.podLine.sub(fieldInfo.podRedeemed);
        await time.increase(60 * 60 + 10);
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
        let tx = await f.farmContract.connect(f.wallets.admin).sunrise();
        let receipt = await tx.wait();
        let growSupplyEvent = receipt.events?.find((e) => e.event === 'SupplyMinted');
        expect(growSupplyEvent?.args?.[2]).equal(expectedForPod);
      });
      it('should calculate Melon for Silo and Pod correctly (when PodLine is large)', async function () {
        const f = await loadFixture(deployFarm);
        // make field has some available soil
        for (let i = 0; i < 10; i++) {
          await time.increase(60 * 60 + 10);
          await f.oracleContract.setAssetPrice(
            ethers.utils.parseUnits('0.5', 36).div(f.ethUsdPrice),
          );
          await f.farmContract.connect(f.wallets.admin).sunrise();
        }
        await f.melonTokenContract
          .connect(f.wallets.admin)
          .approve(f.farmContractAddress, ethers.utils.parseEther('1000'));
        await f.farmContract
          .connect(f.wallets.admin)
          .fieldPurchasePod(f.wallets.admin.address, ethers.utils.parseEther('1000'));
        const fieldInfo = await f.farmContract.field();
        const currentMelonNeedForPod = fieldInfo.podLine.sub(fieldInfo.podRedeemed);
        let deltaSupply = await f.farmContract.getSupplyDelta();
        // try to make deltaSupply > 0 by increase MELON price
        while (deltaSupply.lt(0)) {
          await time.increase(60 * 60 + 10);
          await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
          deltaSupply = await f.farmContract.getSupplyDelta();
        }
        const newMelon = deltaSupply.mul(618).div(1000); // 61.8% of deltaSupply
        const expectedMelonForPod = newMelon.mul(40).div(100); // 40% of deltaSupply
        expect(expectedMelonForPod).to.be.lt(currentMelonNeedForPod); // Melon need for Pod is bigger than expected Melon for Pod
        await time.increase(60 * 60 + 10);
        let tx = await f.farmContract.connect(f.wallets.admin).sunrise();
        let receipt = await tx.wait();
        let growSupplyEvent = receipt.events?.find((e) => e.event === 'SupplyMinted');
        expect(growSupplyEvent?.args?.[2]).equal(expectedMelonForPod);
      });
    });

    describe('#updateField', function () {
      it('should calculate available soil correctly when deltaSupply negative', async function () {
        const f = await loadFixture(deployFarm);
        await time.increase(60 * 60 + 10);
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        const deltaSupply = await f.farmContract.getSupplyDelta();
        expect(deltaSupply).to.be.lt(0);
        const expectedAvailableSoil = deltaSupply.mul(-1);
        const tx = await f.farmContract.connect(f.wallets.admin).sunrise();
        const receipt = await tx.wait();
        const PodMintedEvent = receipt.events?.find((e) => e.event === 'PodMinted');
        expect(PodMintedEvent?.args?.[1]).to.be.equal(expectedAvailableSoil);
      });
      it('should calculate available soil correctly when deltaSupply positive', async function () {
        const f = await loadFixture(deployFarm);
        await time.increase(60 * 60 + 10);
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
        const deltaSupply = await f.farmContract.getSupplyDelta();
        expect(deltaSupply).to.be.gt(0);
        const expectedAvailableSoil = deltaSupply.div(100); // 1% of deltaSupply
        const tx = await f.farmContract.connect(f.wallets.admin).sunrise();
        const receipt = await tx.wait();
        const PodMintedEvent = receipt.events?.find((e) => e.event === 'PodMinted');
        expect(PodMintedEvent?.args?.[1]).to.be.equal(expectedAvailableSoil);
      });
    });
  });
});
