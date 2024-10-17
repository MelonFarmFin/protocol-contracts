import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ethers } from 'hardhat';

describe('Melon', function () {
  async function deployMelonToken() {
    const signers = await ethers.getSigners();
    const factory = await ethers.getContractFactory('Melon');

    const melonTokenContract = await factory.deploy();
    const melonTokenAddress = melonTokenContract.address;

    // Generate 10 random addresses for experiments.
    const randomAddresses = Array.from({ length: 10 }, () => ethers.Wallet.createRandom().address);

    return {
      melonTokenContract,
      melonTokenAddress,
      wallets: {
        deployer: signers[0],
        holderA: signers[1],
        holderB: signers[2],
        holderC: signers[3],
        holderD: signers[4],
      },
      randomAddresses,
    };
  }

  describe('#constructor', function () {
    it('should be deployed correctly', async function () {
      const f = await loadFixture(deployMelonToken);

      const owner = await f.melonTokenContract.owner();
      const totalSupply = await f.melonTokenContract.totalSupply();

      // owner is the deployer address
      expect(owner).equal(f.wallets.deployer.address);

      // no token minted yet
      expect(totalSupply).equal(0n);
    });
  });
});
