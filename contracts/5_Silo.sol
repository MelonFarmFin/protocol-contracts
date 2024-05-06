//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Book} from "./0_Book.sol";
import {Field} from "./4_Field.sol";
import {IMelonAsset} from "./interfaces/IMelonAsset.sol";

contract Silo is Field {
    event Deposited(
        address indexed owner,
        uint256 indexed depositId,
        uint256 indexed amount,
        uint256 seeds
    );
    event Withdrawn(
        address indexed owner,
        uint256 indexed depositId,
        uint256 indexed amount,
        uint256 melons
    );

    error InvalidAmount();
    error DepositStillLocked();
    error NotDepositOwner();

    // transfer token amount from caller
    // and issue deposit asset to depositor
    function depositFor(
        address caller,
        address depositor,
        uint256 poolId,
        uint256 amount
    ) internal {
        if (amount == 0) {
            revert InvalidAmount();
        }

        uint256 seeds = (pools[poolId].seedPerToken * amount) / 1e18;

        // add incentive seeds if any
        int256 deltaPrice = getPriceDelta();
        if (deltaPrice < 0) {
            seeds = seeds + ((seeds * uint256(-deltaPrice)) / 1e18);
        }

        // update total seeds
        silo.totalSeeds = silo.totalSeeds + seeds;

        // calculate melon debts
        uint256 melonDebts = (silo.totalMelons * seeds) / silo.totalSeeds;

        // add new Deposit position
        silo.deposits[silo.nextDepositId] = DepositInfo({
            poolId: poolId,
            season: season.current,
            amount: amount,
            melonDebts: melonDebts,
            melonGrowth: 0,
            seeds: seeds,
            seedPlantSeason: season.current
        });

        // mint Deposit NFT
        IMelonAsset(silo.asset).mint(depositor, silo.nextDepositId);

        // transfer token into Farm
        IERC20(pools[poolId].token).transferFrom(caller, address(this), amount);

        emit Deposited(depositor, silo.nextDepositId, amount, seeds);

        silo.nextDepositId = silo.nextDepositId + 1;
    }

    // owner plant growth seeds
    function plantSeeds(uint256 depositId) internal {
        address owner = IMelonAsset(silo.asset).ownerOf(depositId);
        if (owner != owner) {
            revert NotDepositOwner();
        }

        uint256 growthMelons = getGrowthMelons(depositId);
        uint256 growthSeeds = getGrowthSeeds(depositId);

        // add pending Melons to growth balance
        silo.deposits[depositId].melonGrowth = growthMelons;

        // update new seeds balance
        silo.deposits[depositId].seeds = silo.deposits[depositId].seeds + growthSeeds;
        silo.deposits[depositId].seedPlantSeason = season.current;

        // update Melons debts with new seeds balance
        silo.deposits[depositId].melonDebts =
            (silo.totalMelons * silo.deposits[depositId].seeds) /
            silo.totalSeeds;
    }

    // caller call withdrawn position of caller
    // transfer token and Melons to recipient too
    function withdrawFor(address caller, address recipient, uint256 depositId) internal {
        address owner = IMelonAsset(silo.asset).ownerOf(depositId);
        if (owner != caller) {
            revert NotDepositOwner();
        }

        // must pass the locking period
        uint256 seasonPassed = season.current - silo.deposits[depositId].season;
        if (seasonPassed < Book.SeasonDepositLocked) {
            revert DepositStillLocked();
        }

        // plant seeds
        plantSeeds(depositId);

        // transfer growth Melons
        IERC20(melon).transfer(recipient, silo.deposits[depositId].melonGrowth);

        // transfer assets
        IERC20(pools[silo.deposits[depositId].poolId].token).transfer(
            recipient,
            silo.deposits[depositId].amount
        );

        emit Withdrawn(
            caller,
            depositId,
            silo.deposits[depositId].amount,
            silo.deposits[depositId].melonGrowth
        );

        // delete deposit position
        delete silo.deposits[depositId];

        // burn deposit NFT
        IMelonAsset(silo.asset).burn(depositId);
    }
}
