// // FIXME: This test is only working on local network

// import chai, { expect } from 'chai';
// import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
// import { ethers } from 'hardhat';
// import { WrapperBuilder } from '@redstone-finance/evm-connector';
// import { BigNumber } from 'ethers';
// import { solidity } from 'ethereum-waffle';

// chai.use(solidity);

// describe('MelonOracle', function () {
//   async function deployMelonOracle() {
//     const signers = await ethers.getSigners();

//     // DEPLOY TOKEN AND INIT UNISWAP PAIR
//     const erc20Factory = await ethers.getContractFactory('TestERC20');
//     const wethToken = await erc20Factory.deploy('Wrapped Ether', 'WETH');
//     const melonToken = await erc20Factory.deploy('Melon', 'MELON');
//     await wethToken
//       .connect(signers[0])
//       .mint(signers[0].address, ethers.utils.parseEther('1000000'));
//     await melonToken
//       .connect(signers[0])
//       .mint(signers[0].address, ethers.utils.parseEther('2000000000'));

//     const uniswapV2FactoryFactory = await ethers.getContractFactory('MockUniswapV2Factory');
//     const uniswapV2Factory = await uniswapV2FactoryFactory.deploy();
//     await uniswapV2Factory.createPair(melonToken.address, wethToken.address);

//     // DEPLOY CHAINLINK MOCK AGGREGATOR
//     const mockAggregatorFactory = await ethers.getContractFactory('MockAggregatorV3');
//     const mockAggregator = await mockAggregatorFactory.deploy(BigNumber.from(100000000000), 8); // 1000USD

//     // DEPLOY MELON ORACLE
//     const melonOracleFactory = await ethers.getContractFactory('MelonOracle');
//     const melonOracle = await melonOracleFactory.deploy(
//       signers[0].address,
//       mockAggregator.address,
//       uniswapV2Factory.address,
//       melonToken.address,
//       wethToken.address,
//       24 * 60 * 60, // 1 day
//       24 // 1 per hour
//     );
//     const wrappedMelonOracle = WrapperBuilder.wrap(melonOracle).usingDataService({
//       dataFeeds: ['ETH'],
//     });
//     return {
//       melonOracle,
//       wrappedMelonOracle,
//       mockAggregator,
//       melonToken,
//       wethToken,
//       wallets: {
//         deployer: signers[0],
//         user1: signers[1],
//         user2: signers[2],
//       },
//     };
//   }
//   describe('#getEthPrice', function () {
//     it('should return the chainlink price first', async function () {
//       const f = await loadFixture(deployMelonOracle);
//       const price = await f.wrappedMelonOracle.getEthPrice();
//       expect(price).equal(ethers.utils.parseEther('1000')); // 1000USD
//       await f.mockAggregator.setPrice(BigNumber.from(200000000000)); // 2000USD
//       const price2 = await f.wrappedMelonOracle.getEthPrice();
//       expect(price2).equal(ethers.utils.parseEther('2000')); // 2000USD
//     });
//     it('should return the Redstone price if chainlink expired 5mins', async function () {
//       const f = await loadFixture(deployMelonOracle);
//       const price = await f.wrappedMelonOracle.getEthPrice();
//       expect(price).equal(ethers.utils.parseEther('1000')); // 1000USD

//       await f.mockAggregator.setUpdatedAt(Math.floor(Date.now() / 1000) - 301); // 5mins ago
//       const price2 = await f.wrappedMelonOracle.getEthPrice();
//       expect(price2).not.equal(ethers.utils.parseEther('1000')); // 1000USD

//       await f.mockAggregator.setPrice(BigNumber.from(200000000000)); // 2000USD
//       const price3 = await f.wrappedMelonOracle.getEthPrice();
//       expect(price3).equal(ethers.utils.parseEther('2000')); // 2000USD
//     });
//   });
// });
