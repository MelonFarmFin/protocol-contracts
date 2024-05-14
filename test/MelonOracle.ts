import chai, { expect } from 'chai';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { ethers } from 'hardhat';
import { WrapperBuilder } from '@redstone-finance/evm-connector';
import { BigNumber } from 'ethers';
import { solidity } from 'ethereum-waffle';
import { IUniswapV2Factory__factory, IUniswapV2Router__factory } from '../typechain-types';

chai.use(solidity);

describe('MelonOracle', function () {
  async function deployMelonOracle() {
    const UNISWAP_V2_FACTORY_BASE = '0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6';
    const UNISWAP_V2_ROUTER_BASE = '0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24';

    const signers = await ethers.getSigners();

    // DEPLOY TOKEN AND INIT UNISWAP PAIR
    const erc20Factory = await ethers.getContractFactory('TestERC20');
    const wethToken = await erc20Factory.deploy('Wrapped Ether', 'WETH');
    const melonToken = await erc20Factory.deploy('Melon', 'MELON');
    await wethToken
      .connect(signers[0])
      .mint(signers[0].address, ethers.utils.parseEther('1000000'));
    await melonToken
      .connect(signers[0])
      .mint(signers[0].address, ethers.utils.parseEther('2000000000'));

    const uniswapV2Factory = IUniswapV2Factory__factory.connect(
      UNISWAP_V2_FACTORY_BASE,
      signers[0]
    );
    const uniswapV2Router = IUniswapV2Router__factory.connect(UNISWAP_V2_ROUTER_BASE, signers[0]);
    await uniswapV2Factory.createPair(melonToken.address, wethToken.address);
    await melonToken
      .connect(signers[0])
      .approve(UNISWAP_V2_ROUTER_BASE, ethers.constants.MaxUint256);
    await wethToken
      .connect(signers[0])
      .approve(UNISWAP_V2_ROUTER_BASE, ethers.constants.MaxUint256);
    await uniswapV2Router.addLiquidity(
      melonToken.address,
      wethToken.address,
      ethers.utils.parseEther('2000000'),
      ethers.utils.parseEther('1000'),
      0,
      0,
      signers[0].address,
      Math.floor(Date.now() / 1000) + 1000000
    );

    // DEPLOY CHAINLINK MOCK AGGREGATOR
    const mockAggregatorFactory = await ethers.getContractFactory('MockAggregatorV3');
    const mockAggregator = await mockAggregatorFactory.deploy(BigNumber.from(100000000000), 8); // 1000USD

    // DEPLOY MELON ORACLE
    const melonOracleFactory = await ethers.getContractFactory('MelonOracle');
    const currentBlockTime = await time.latest();
    const melonOracle = await melonOracleFactory.deploy(
      signers[0].address,
      mockAggregator.address,
      UNISWAP_V2_FACTORY_BASE,
      melonToken.address,
      wethToken.address,
      24 * 60 * 60, // 1 day
      24, // 1 per hour,
      currentBlockTime + 60 * 60 // start after 1 hour
    );
    const wrappedMelonOracle = WrapperBuilder.wrap(melonOracle).usingDataService({
      dataFeeds: ['ETH'],
    });
    return {
      melonOracle,
      wrappedMelonOracle,
      mockAggregator,
      uniswapV2Router,
      melonToken,
      wethToken,
      wallets: {
        deployer: signers[0],
        user1: signers[1],
        user2: signers[2],
      },
    };
  }

  describe('#constructor', function () {
    it('should be deployed correctly', async function () {
      const f = await loadFixture(deployMelonOracle);
      const adminAddress = await f.wrappedMelonOracle.getAdmin();
      expect(adminAddress).equal(f.wallets.deployer.address);
    });
  });
  describe('#startTime', function () {
    it('should be reverted when call update and return 0 when get price before start time', async function () {
      const f = await loadFixture(deployMelonOracle);
      await expect(f.wrappedMelonOracle.connect(f.wallets.deployer).update()).to.be.reverted;
      const ethPrice = await f.wrappedMelonOracle.getEthPrice();
      expect(ethPrice).to.be.eq(0);
      const melonEthPrice = await f.wrappedMelonOracle.getAssetPrice(f.melonToken.address);
      expect(melonEthPrice).to.be.eq(0);
    });
    it('should be able to update after start time', async function () {
      const f = await loadFixture(deployMelonOracle);
      await time.increase(60 * 60); // 1 hour
      await expect(f.wrappedMelonOracle.connect(f.wallets.deployer).update()).not.to.be.reverted;
      await f.mockAggregator.setPrice(ethers.BigNumber.from('200000000000')); // 2000USD
      const ethPrice = await f.wrappedMelonOracle.getEthPrice();
      expect(ethPrice).to.be.eq(ethers.utils.parseEther('2000'));
    });
    describe('#update', function () {
      it('should be call by admin only', async function () {
        const f = await loadFixture(deployMelonOracle);
        await time.increase(60 * 60); // 1 hour
        await expect(f.wrappedMelonOracle.connect(f.wallets.user1).update()).to.be.reverted;
        await f.wrappedMelonOracle.connect(f.wallets.deployer).update();
      });
    });
    describe('#getMelonUsdPrice', function () {
      it('should revert when missing historical data', async function () {
        const f = await loadFixture(deployMelonOracle);
        // update 24 times
        for (let i = 0; i < 24; i++) {
          await time.increase(60 * 60); // 1 hour
          await f.wrappedMelonOracle.connect(f.wallets.deployer).update();
          await f.mockAggregator.setPrice(ethers.BigNumber.from('200000000000')); // 2000USD
        }
        await expect(f.wrappedMelonOracle.getMelonUsdPrice()).not.to.be.reverted;
        await time.increase(60 * 60); // 1 hour
        for (let i = 0; i < 23; i++) {
          await time.increase(60 * 60); // 1 hour
          await f.wrappedMelonOracle.connect(f.wallets.deployer).update();
          await f.mockAggregator.setPrice(ethers.BigNumber.from('200000000000')); // 2000USD
        }
        await expect(f.wrappedMelonOracle.getMelonUsdPrice()).to.be.reverted;
      });

      it('should log the Melon USD price correctly', async function () {
        const f = await loadFixture(deployMelonOracle);
        // update 24 times
        for (let i = 0; i < 24; i++) {
          await time.increase(60 * 60); // 1 hour
          await f.wrappedMelonOracle.connect(f.wallets.deployer).update();
          await f.mockAggregator.setPrice(ethers.BigNumber.from('200000000000')); // 2000USD
        }
        const price = await f.wrappedMelonOracle.getMelonUsdPrice();
        console.log('price', ethers.utils.formatEther(price));
        // doing  swap then update and show Melon USD price
        for (let i = 0; i < 24; i++) {
          if (i % 2 == 0) {
            // swap MELON -> WETH
            await f.uniswapV2Router
              .connect(f.wallets.deployer)
              .swapExactTokensForTokens(
                ethers.utils.parseEther('1000'),
                0,
                [f.melonToken.address, f.wethToken.address],
                f.wallets.deployer.address,
                ethers.constants.MaxUint256
              );
          } else {
            // swap WETH -> MELON
            await f.uniswapV2Router
              .connect(f.wallets.deployer)
              .swapExactTokensForTokens(
                ethers.utils.parseEther('1'),
                0,
                [f.wethToken.address, f.melonToken.address],
                f.wallets.deployer.address,
                ethers.constants.MaxUint256
              );
          }
          await time.increase(60 * 60); // 1 hour
          await f.wrappedMelonOracle.connect(f.wallets.deployer).update();
          await f.mockAggregator.setPrice(ethers.BigNumber.from('200000000000')); // 2000USD
          console.log(
            'price',
            ethers.utils.formatEther(await f.wrappedMelonOracle.getMelonUsdPrice())
          );
        }
      });
    });
  });
});