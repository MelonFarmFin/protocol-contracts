import chai, { expect } from 'chai';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { ethers, network } from 'hardhat';
import { solidity } from 'ethereum-waffle';

chai.use(solidity);

describe('Field', function () {
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

  describe('#purchasePodFor', function () {
    it('should revert when amount is ZERO', async function () {
      const f = await loadFixture(deployFarm);
      await expect(f.farmContract.fieldPurchasePod(f.randomAddresses[0], 0)).to.be.revertedWith(
        'InvalidInputAmount',
      );
    });
    it('should revert when available soil smaller than amount', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const fieldInfo = await f.farmContract.field();
      const availableSoil = fieldInfo.soilAvailable;
      const amount = ethers.utils.parseEther('500');
      expect(availableSoil).to.be.lt(amount);
      await f.melonTokenContract.connect(f.wallets.admin).approve(f.farmContractAddress, amount);
      await expect(
        f.farmContract.fieldPurchasePod(f.randomAddresses[0], amount),
      ).to.be.revertedWith('InsufficientInputAmount');
    });
    it('should purchase success when amount is valid', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const fieldInfo = await f.farmContract.field();
      const availableSoil = fieldInfo.soilAvailable;
      const amount = ethers.utils.parseEther('100');
      expect(availableSoil).to.be.gte(amount);
      await f.melonTokenContract.connect(f.wallets.admin).approve(f.farmContractAddress, amount);
      const tx = await f.farmContract.fieldPurchasePod(f.randomAddresses[0], amount);
      const receipt = await tx.wait();
      const podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).to.not.be.undefined;
    });
    it('should calculate pod correctly', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const fieldInfo = await f.farmContract.field();
      const availableSoil = fieldInfo.soilAvailable;
      const amount = ethers.utils.parseEther('100');
      expect(availableSoil).to.be.gte(amount);
      const fieldTemperature = fieldInfo.temperature;
      const expectedPod = amount.add(
        amount.mul(fieldTemperature).div(ethers.utils.parseEther('1')),
      );
      await f.melonTokenContract.connect(f.wallets.admin).approve(f.farmContractAddress, amount);
      const tx = await f.farmContract.fieldPurchasePod(f.randomAddresses[0], amount);
      const receipt = await tx.wait();
      const podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).to.not.be.undefined; // for tx success
      const pod = podPurchasedEvent?.args?.[4];
      expect(pod).to.be.eq(expectedPod);
    });
    it('should mint Pod NFT for recipient', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const fieldInfo = await f.farmContract.field();
      const availableSoil = fieldInfo.soilAvailable;
      const amount = ethers.utils.parseEther('100');
      expect(availableSoil).to.be.gte(amount);
      await f.melonTokenContract.connect(f.wallets.admin).approve(f.farmContractAddress, amount);
      const recipient = f.randomAddresses[0];
      const tx = await f.farmContract.fieldPurchasePod(recipient, amount);
      const receipt = await tx.wait();
      const podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).to.not.be.undefined; // for tx success
      const podId = podPurchasedEvent?.args?.[2];
      const owner = await f.podNft.ownerOf(podId);
      expect(owner).to.be.eq(recipient);
    });
    it('should update the podLine and podIndex correctly', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      let fieldInfo = await f.farmContract.field();
      const lastPodLine = fieldInfo.podLine;
      const lastNextPodIndex = fieldInfo.nextPodId;
      const availableSoil = fieldInfo.soilAvailable;
      const amount = ethers.utils.parseEther('100');
      expect(availableSoil).to.be.gte(amount);
      await f.melonTokenContract.connect(f.wallets.admin).approve(f.farmContractAddress, amount);
      const recipient = f.randomAddresses[0];
      const tx = await f.farmContract.fieldPurchasePod(recipient, amount);
      const receipt = await tx.wait();
      const podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).to.not.be.undefined; // for tx success
      const pod = podPurchasedEvent?.args?.[4];
      fieldInfo = await f.farmContract.field();
      expect(fieldInfo.podLine).to.be.eq(lastPodLine.add(pod));
      expect(fieldInfo.nextPodId).to.be.eq(lastNextPodIndex.add(1));
    });
  });
  describe('#redeemPodFor', function () {
    it('should revert when pod NFT is redeemed', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const amount = ethers.utils.parseEther('100');
      await f.melonTokenContract.connect(f.wallets.admin).approve(f.farmContractAddress, amount);
      let tx = await f.farmContract.fieldPurchasePod(f.wallets.admin.address, amount);
      let receipt = await tx.wait();
      const podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).not.to.be.undefined; // for tx success
      const podId = podPurchasedEvent?.args?.[2];
      const owner = await f.podNft.ownerOf(podId);
      expect(owner).to.be.eq(f.wallets.admin.address);
      // create MELON for Field
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      tx = await f.farmContract.fieldRedeemPod(f.wallets.admin.address, podId);
      receipt = await tx.wait();
      const podRedeemedEvent = receipt.events?.find((e) => e.event === 'PodRedeemed');
      expect(podRedeemedEvent).not.to.be.undefined; // for tx success
      await expect(
        f.farmContract.fieldRedeemPod(f.wallets.admin.address, podId),
      ).to.be.revertedWith('PodAlreadyRedeemed');
    });
    it('should revert when not owner of pod NFT', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const amount = ethers.utils.parseEther('100');
      await f.melonTokenContract.connect(f.wallets.admin).approve(f.farmContractAddress, amount);
      const recipient = f.randomAddresses[0];
      const tx = await f.farmContract.fieldPurchasePod(recipient, amount);
      const receipt = await tx.wait();
      const podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).to.not.be.undefined; // for tx success
      const podId = podPurchasedEvent?.args?.[2];
      const owner = await f.podNft.ownerOf(podId);
      expect(owner).not.to.be.eq(f.wallets.admin);
      await expect(
        f.farmContract.fieldRedeemPod(f.wallets.admin.address, podId),
      ).to.be.revertedWith('NotPodOwner');
    });
    it('should redeem all pod if pod available enough', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const amount = ethers.utils.parseEther('100');
      await f.melonTokenContract.connect(f.wallets.admin).approve(f.farmContractAddress, amount);
      let tx = await f.farmContract.fieldPurchasePod(f.wallets.admin.address, amount);
      let receipt = await tx.wait();
      const podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).not.to.be.undefined; // for tx success
      const podId = podPurchasedEvent?.args?.[2];
      const pod = podPurchasedEvent?.args?.[4];
      const owner = await f.podNft.ownerOf(podId);
      expect(owner).to.be.eq(f.wallets.admin.address);
      // create MELON for Field
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const fieldInfo = await f.farmContract.field();
      expect(fieldInfo.podRedeemable).to.be.gte(pod);
      const melonBalanceBefore = await f.melonTokenContract.balanceOf(f.wallets.admin.address);
      tx = await f.farmContract.fieldRedeemPod(f.wallets.admin.address, podId);
      receipt = await tx.wait();
      const podRedeemedEvent = receipt.events?.find((e) => e.event === 'PodRedeemed');
      expect(podRedeemedEvent).not.to.be.undefined; // for tx success
      const melonBalanceAfter = await f.melonTokenContract.balanceOf(f.wallets.admin.address);
      expect(melonBalanceAfter).to.be.eq(melonBalanceBefore.add(pod));
      // burn the pod NFT
      await expect(f.podNft.ownerOf(podId)).to.be.revertedWith('ERC721: invalid token ID');
    });
    it('should redeem part of pod if pod available not enough', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const amount = ethers.utils.parseEther('100');
      await f.melonTokenContract.connect(f.wallets.admin).approve(f.farmContractAddress, amount);
      let tx = await f.farmContract.fieldPurchasePod(f.wallets.admin.address, amount);
      let receipt = await tx.wait();
      const podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).not.to.be.undefined; // for tx success
      const podId = podPurchasedEvent?.args?.[2];
      const pod = podPurchasedEvent?.args?.[4];
      const owner = await f.podNft.ownerOf(podId);
      expect(owner).to.be.eq(f.wallets.admin.address);
      // create MELON for Field but not greater than pod
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
        const fieldInfo = await f.farmContract.field();
        if (fieldInfo.podRedeemable.gte(0)) {
          break;
        }
      }
      const fieldInfo = await f.farmContract.field();
      expect(fieldInfo.podRedeemable).to.be.lt(pod);
      const melonBalanceBefore = await f.melonTokenContract.balanceOf(f.wallets.admin.address);
      tx = await f.farmContract.fieldRedeemPod(f.wallets.admin.address, podId);
      receipt = await tx.wait();
      const podRedeemedEvent = receipt.events?.find((e) => e.event === 'PodRedeemed');
      expect(podRedeemedEvent).not.to.be.undefined; // for tx success
      const melonBalanceAfter = await f.melonTokenContract.balanceOf(f.wallets.admin.address);
      expect(melonBalanceAfter).to.be.eq(melonBalanceBefore.add(fieldInfo.podRedeemable));
      // NOT burn the pod NFT
      const ownerAfter = await f.podNft.ownerOf(podId);
      expect(ownerAfter).to.be.eq(f.wallets.admin.address);
    });
    it('should revert when not reach lineIndex', async function () {
      const f = await loadFixture(deployFarm);
      // create some available soil
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('0.8', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
      }
      const amount = ethers.utils.parseEther('100');
      await f.melonTokenContract
        .connect(f.wallets.admin)
        .approve(f.farmContractAddress, amount.mul(2));
      let tx = await f.farmContract.fieldPurchasePod(f.wallets.admin.address, amount);
      let receipt = await tx.wait();
      let podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).not.to.be.undefined; // for tx success
      const podId = podPurchasedEvent?.args?.[2];
      const pod = podPurchasedEvent?.args?.[4];
      const owner = await f.podNft.ownerOf(podId);
      expect(owner).to.be.eq(f.wallets.admin.address);
      tx = await f.farmContract.fieldPurchasePod(f.wallets.admin.address, amount);
      receipt = await tx.wait();
      podPurchasedEvent = receipt.events?.find((e) => e.event === 'PodPurchased');
      expect(podPurchasedEvent).not.to.be.undefined; // for tx success
      const podId2 = podPurchasedEvent?.args?.[2];
      const owner2 = await f.podNft.ownerOf(podId2);
      expect(owner2).to.be.eq(f.wallets.admin.address);
      // create MELON for Field but not greater than pod
      for (let i = 0; i < 10; i++) {
        await f.oracleContract.setAssetPrice(ethers.utils.parseUnits('2', 36).div(f.ethUsdPrice));
        await f.farmContract.connect(f.wallets.admin).sunrise();
        await time.increase(60 * 60 + 10);
        const fieldInfo = await f.farmContract.field();
        if (fieldInfo.podRedeemable.gte(0)) {
          break;
        }
      }
      const fieldInfo = await f.farmContract.field();
      expect(fieldInfo.podRedeemable).to.be.lt(pod);
      tx = await f.farmContract.fieldRedeemPod(f.wallets.admin.address, podId);
      receipt = await tx.wait();
      const podRedeemedEvent = receipt.events?.find((e) => e.event === 'PodRedeemed');
      expect(podRedeemedEvent).not.to.be.undefined; // for tx success
      // NOT burn the pod NFT
      const ownerAfter = await f.podNft.ownerOf(podId);
      expect(ownerAfter).to.be.eq(f.wallets.admin.address); // not redeem all pod of podId
      await expect(
        f.farmContract.fieldRedeemPod(f.wallets.admin.address, podId2),
      ).to.be.revertedWith('PodNotRedeemable'); // revert when redeem podId2
    });
  });
});
