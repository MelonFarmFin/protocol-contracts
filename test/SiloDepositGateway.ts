import chai, { expect } from 'chai';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { ethers, network } from 'hardhat';
import { solidity } from 'ethereum-waffle';

chai.use(solidity);

// Base Sepolia Addresses
const PANCAKE_V2_ROUTER_BASE = '0x8cFe327CEc66d1C090Dd72bd0FF11d690C33a2Eb';
const MELON_ADDRESS = '0xe16bd8e17c5b96058a130fe18933ab630a59fddd';
const WETH_ADDRESS = '0x4200000000000000000000000000000000000006';
const LP_MELON_ETH_ADDRESS = '0x67e27b57fefa28472a72c282c44ab834ac0a49a7';
const FARM_ADDRESS = '0x702242f1ee2364383d402dcd7f69e2df9fa9644a';
const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000';
const MELON_HOLDER = '0x574cE92e3f425AAB9dfEBC64ad2544c1Ca01e211';
const USDC_HOLDER = '0xFaEc9cDC3Ef75713b48f46057B98BA04885e3391';

describe('SiloDepositGateway', function () {
  async function deploySiloDepositGateway() {
    {
      await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [MELON_HOLDER],
      });
      await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [USDC_HOLDER],
      });
    }

    const melonHolder = ethers.provider.getSigner(MELON_HOLDER);
    const usdcHolder = ethers.provider.getSigner(USDC_HOLDER);
    await network.provider.send('hardhat_setBalance', [MELON_HOLDER, '0x56BC75E2D63100000']);
    await network.provider.send('hardhat_setBalance', [USDC_HOLDER, '0x56BC75E2D63100000']);
    const signers = await ethers.getSigners();

    // Deploy SiloDepositGateway
    const factory = await ethers.getContractFactory('SiloDepositGateway');
    const siloDepositGatewayContract = await factory.deploy(
      PANCAKE_V2_ROUTER_BASE,
      WETH_ADDRESS,
      MELON_ADDRESS,
      LP_MELON_ETH_ADDRESS,
      FARM_ADDRESS,
    );
    const melonFactory = await ethers.getContractFactory('Melon');
    const melonContract = melonFactory.attach(MELON_ADDRESS);

    const wethContract = await ethers.getContractAt('IWETH', WETH_ADDRESS);
    const usdcContract = await ethers.getContractAt('IERC20', USDC_ADDRESS);
    const farmFactory = await ethers.getContractFactory('Farm');
    const farmContract = farmFactory.attach(FARM_ADDRESS);

    const siloDepositNftAddress = (await farmContract.silo()).asset;
    const siloDepositNftContract = await ethers.getContractAt('IMelonAsset', siloDepositNftAddress);
    return {
      siloDepositGatewayContract,
      siloDepositGatewayAddress: siloDepositGatewayContract.address,
      wethContract,
      usdcContract,
      melonContract,
      farmContract,
      siloDepositNftContract,
      wallets: {
        deployer: signers[0],
        user1: signers[1],
        user2: signers[2],
        melonHolder,
        usdcHolder,
      },
    };
  }

  describe('#constructor', function () {
    it('should be deployed correctly', async function () {
      const f = await loadFixture(deploySiloDepositGateway);
      const admin = await f.siloDepositGatewayContract.getAdmin();
      expect(admin).equal(f.wallets.deployer.address);
      expect(await f.siloDepositGatewayContract.isValidTokenIn(MELON_ADDRESS)).to.be.true;
      expect(await f.siloDepositGatewayContract.isValidTokenIn(WETH_ADDRESS)).to.be.true;
      expect(
        await f.siloDepositGatewayContract.isValidTokenIn(
          '0x0000000000000000000000000000000000000000',
        ),
      ).to.be.true;
    });
  });
  describe('#siloDeposit', function () {
    describe('deposit failed with invalid params', function () {
      it('should revert with invalid poolId', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        await expect(
          f.siloDepositGatewayContract
            .connect(f.wallets.user1)
            .siloDeposit(
              2,
              WETH_ADDRESS,
              ethers.utils.parseEther('0.1'),
              ethers.BigNumber.from('50'),
            ),
        ).to.be.revertedWith('SiloDepositGateway__InvalidPoolId()');
      });
      it('should revert with amount is zero', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        await expect(
          f.siloDepositGatewayContract
            .connect(f.wallets.user1)
            .siloDeposit(
              0,
              WETH_ADDRESS,
              ethers.utils.parseEther('0'),
              ethers.BigNumber.from('50'),
            ),
        ).to.be.revertedWith('SiloDepositGateway__MustGreaterThanZero()');
        await expect(
          f.siloDepositGatewayContract
            .connect(f.wallets.user1)
            .siloDeposit(
              0,
              MELON_ADDRESS,
              ethers.utils.parseEther('0'),
              ethers.BigNumber.from('50'),
            ),
        ).to.be.revertedWith('SiloDepositGateway__MustGreaterThanZero()');
        await expect(
          f.siloDepositGatewayContract
            .connect(f.wallets.user1)
            .siloDeposit(
              0,
              ADDRESS_ZERO,
              ethers.utils.parseEther('100'),
              ethers.BigNumber.from('50'),
              {
                value: ethers.utils.parseEther('0'),
              },
            ),
        ).to.be.revertedWith('SiloDepositGateway__MustGreaterThanZero()');
      });
      it('should revert with invalid slippage', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        await expect(
          f.siloDepositGatewayContract
            .connect(f.wallets.user1)
            .siloDeposit(
              0,
              WETH_ADDRESS,
              ethers.utils.parseEther('0'),
              ethers.BigNumber.from('50'),
            ),
        ).to.be.revertedWith('SiloDepositGateway__MustGreaterThanZero()');
      });
    });
    describe('deposit success with PoolId = 0', function () {
      it('should deposit correctly with poolId = 0 and tokenIn is WETH', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        const siloInfo = await f.farmContract.silo();
        const tokenId = await siloInfo.nextDepositId;
        await f.wethContract
          .connect(f.wallets.user1)
          .deposit({ value: ethers.utils.parseEther('1') });
        await f.wethContract
          .connect(f.wallets.user1)
          .approve(f.siloDepositGatewayAddress, ethers.utils.parseEther('0.1'));
        const tx = await f.siloDepositGatewayContract
          .connect(f.wallets.user1)
          .siloDeposit(
            0,
            WETH_ADDRESS,
            ethers.utils.parseEther('0.1'),
            ethers.BigNumber.from('50'),
          ); //swapSlippage = 50 = 0.5%
        const receipt = await tx.wait();
        const siloDepositEvent = receipt.events?.find((e) => e.event === 'SiloDeposit');
        expect(siloDepositEvent).not.undefined;
        expect(await f.siloDepositNftContract.ownerOf(tokenId)).equal(f.wallets.user1.address);
      });
      it('should deposit correctly with poolId = 0 and tokenIn is ETH', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        const siloInfo = await f.farmContract.silo();
        const tokenId = await siloInfo.nextDepositId;
        const tx = await f.siloDepositGatewayContract
          .connect(f.wallets.user1)
          .siloDeposit(
            0,
            ADDRESS_ZERO,
            ethers.utils.parseEther('0.1'),
            ethers.BigNumber.from('50'),
            {
              value: ethers.utils.parseEther('0.1'),
            },
          ); //swapSlippage = 50 = 0.5%
        const receipt = await tx.wait();
        const siloDepositEvent = receipt.events?.find((e) => e.event === 'SiloDeposit');
        expect(siloDepositEvent).not.undefined;
        expect(await f.siloDepositNftContract.ownerOf(tokenId)).equal(f.wallets.user1.address);
      });
      it('should deposit correctly with poolId = 0 and tokenIn is MELON', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        const siloInfo = await f.farmContract.silo();
        const tokenId = await siloInfo.nextDepositId;
        await f.melonContract
          .connect(f.wallets.melonHolder)
          .approve(f.siloDepositGatewayAddress, ethers.utils.parseEther('100'));
        const tx = await f.siloDepositGatewayContract
          .connect(f.wallets.melonHolder)
          .siloDeposit(
            0,
            MELON_ADDRESS,
            ethers.utils.parseEther('100'),
            ethers.BigNumber.from('50'),
          ); //swapSlippage = 50 = 0.5% (Slippage is not used in this case)
        const receipt = await tx.wait();
        const siloDepositEvent = receipt.events?.find((e) => e.event === 'SiloDeposit');
        expect(siloDepositEvent).not.undefined;
        expect(await f.siloDepositNftContract.ownerOf(tokenId)).equal(MELON_HOLDER);
      });
      it('should deposit correctly with poolId = 0 and tokenIn is USDC', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        // add USDC to allowed tokens
        await f.siloDepositGatewayContract
          .connect(f.wallets.deployer)
          .addAllowedTokenIn([USDC_ADDRESS]);
        const siloInfo = await f.farmContract.silo();
        const tokenId = await siloInfo.nextDepositId;
        await f.usdcContract
          .connect(f.wallets.usdcHolder)
          .approve(f.siloDepositGatewayAddress, ethers.BigNumber.from('10000000')); // 10 USDC
        const tx = await f.siloDepositGatewayContract
          .connect(f.wallets.usdcHolder)
          .siloDeposit(
            0,
            USDC_ADDRESS,
            ethers.BigNumber.from('10000000'),
            ethers.BigNumber.from('50'),
          ); //swapSlippage = 50 = 0.5% (Slippage is not used in this case)
        const receipt = await tx.wait();
        const siloDepositEvent = receipt.events?.find((e) => e.event === 'SiloDeposit');
        expect(siloDepositEvent).not.undefined;
        expect(await f.siloDepositNftContract.ownerOf(tokenId)).equal(USDC_HOLDER);
      });
    });
    describe('deposit success with PoolId = 1', function () {
      it('should deposit correctly with poolId = 1 and tokenIn is WETH', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        const siloInfo = await f.farmContract.silo();
        const tokenId = await siloInfo.nextDepositId;
        await f.wethContract
          .connect(f.wallets.user1)
          .deposit({ value: ethers.utils.parseEther('1') });
        await f.wethContract
          .connect(f.wallets.user1)
          .approve(f.siloDepositGatewayAddress, ethers.utils.parseEther('0.2'));
        const tx = await f.siloDepositGatewayContract
          .connect(f.wallets.user1)
          .siloDeposit(
            1,
            WETH_ADDRESS,
            ethers.utils.parseEther('0.2'),
            ethers.BigNumber.from('50'),
          ); //swapSlippage = 50 = 0.5%
        const receipt = await tx.wait();
        const siloDepositEvent = receipt.events?.find((e) => e.event === 'SiloDeposit');
        expect(siloDepositEvent).not.undefined;
        expect(await f.siloDepositNftContract.ownerOf(tokenId)).equal(f.wallets.user1.address);
      });
      it('should deposit correctly with poolId = 1 and tokenIn is ETH', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        const siloInfo = await f.farmContract.silo();
        const tokenId = await siloInfo.nextDepositId;
        const tx = await f.siloDepositGatewayContract
          .connect(f.wallets.user1)
          .siloDeposit(
            1,
            ADDRESS_ZERO,
            ethers.utils.parseEther('0.2'),
            ethers.BigNumber.from('50'),
            {
              value: ethers.utils.parseEther('0.2'),
            },
          ); //swapSlippage = 50 = 0.5%
        const receipt = await tx.wait();
        const siloDepositEvent = receipt.events?.find((e) => e.event === 'SiloDeposit');
        expect(siloDepositEvent).not.undefined;
        expect(await f.siloDepositNftContract.ownerOf(tokenId)).equal(f.wallets.user1.address);
      });
      it('should deposit correctly with poolId = 1 and tokenIn is MELON', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        const siloInfo = await f.farmContract.silo();
        const tokenId = await siloInfo.nextDepositId;
        await f.melonContract
          .connect(f.wallets.melonHolder)
          .approve(f.siloDepositGatewayAddress, ethers.utils.parseEther('100'));
        const tx = await f.siloDepositGatewayContract
          .connect(f.wallets.melonHolder)
          .siloDeposit(
            1,
            MELON_ADDRESS,
            ethers.utils.parseEther('100'),
            ethers.BigNumber.from('50'),
          ); //swapSlippage = 50 = 0.5% (Slippage is not used in this case)
        const receipt = await tx.wait();
        const siloDepositEvent = receipt.events?.find((e) => e.event === 'SiloDeposit');
        expect(siloDepositEvent).not.undefined;
        expect(await f.siloDepositNftContract.ownerOf(tokenId)).equal(MELON_HOLDER);
      });
      it('should deposit correctly with poolId = 1 and tokenIn is USDC', async function () {
        const f = await loadFixture(deploySiloDepositGateway);
        // add USDC to allowed tokens
        await f.siloDepositGatewayContract
          .connect(f.wallets.deployer)
          .addAllowedTokenIn([USDC_ADDRESS]);
        const siloInfo = await f.farmContract.silo();
        const tokenId = await siloInfo.nextDepositId;
        await f.usdcContract
          .connect(f.wallets.usdcHolder)
          .approve(f.siloDepositGatewayAddress, ethers.BigNumber.from('20000000')); // 20 USDC
        const tx = await f.siloDepositGatewayContract
          .connect(f.wallets.usdcHolder)
          .siloDeposit(
            1,
            USDC_ADDRESS,
            ethers.BigNumber.from('20000000'),
            ethers.BigNumber.from('50'),
          ); //swapSlippage = 50 = 0.5% (Slippage is not used in this case)
        const receipt = await tx.wait();
        const siloDepositEvent = receipt.events?.find((e) => e.event === 'SiloDeposit');
        expect(siloDepositEvent).not.undefined;
        expect(await f.siloDepositNftContract.ownerOf(tokenId)).equal(USDC_HOLDER);
      });
    });
  });
});
