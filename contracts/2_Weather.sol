//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Book} from "./0_Book.sol";
import {Storage} from "./1_Storage.sol";
import {IOracle} from "./interfaces/IOracle.sol";

// Weather helps to calculate core farm metrics after every season
contract Weather is Storage {
    int256 private constant PerfectBalance = 1e18;

    function getSupplyDelta() public view returns (int256) {
        uint256 melonPriceVsEth = IOracle(oracle).getAssetPrice(melon);
        uint256 ethPriceVsUsd = IOracle(oracle).getEthPrice();

        int256 melonSupply = int256(IERC20(melon).totalSupply());
        int256 melonPriceVsUSd = int256((melonPriceVsEth * ethPriceVsUsd) / 1e18);

        int256 melonPriceDiff = melonPriceVsUSd - PerfectBalance;

        return (melonSupply * melonPriceDiff) / melonPriceVsUSd;
    }

    function getPriceDelta() public view returns (int256) {
        uint256 melonPriceVsEth = IOracle(oracle).getAssetPrice(melon);
        uint256 ethPriceVsUsd = IOracle(oracle).getEthPrice();

        int256 melonPriceVsUSd = int256((melonPriceVsEth * ethPriceVsUsd) / 1e18);

        return melonPriceVsUSd - PerfectBalance;
    }

    function getGrowthMelons(uint256 depositId) public view returns (uint256) {
        // include debts
        uint256 totalMelons = (silo.totalMelons * silo.deposits[depositId].seeds) / silo.totalSeeds;

        // pending - claimable
        uint256 pendingMelons = totalMelons > silo.deposits[depositId].melonDebts
            ? totalMelons - silo.deposits[depositId].melonDebts
            : 0;

        // total Melons can be claimed
        return silo.deposits[depositId].melonGrowth + pendingMelons;
    }

    function getGrowthSeeds(uint256 depositId) public view returns (uint256) {
        uint256 depositedSeasons = season.current - silo.deposits[depositId].season;

        uint256 level;
        if (depositedSeasons == 1 || depositedSeasons == 2) {
            level = depositedSeasons;
        } else {
            uint256 previous = 1;
            uint256 current = 2;
            while (current < depositedSeasons) {
                current = current + previous;
                previous = current - previous;
                if (current == depositedSeasons) {
                    level = current;
                } else if (current > depositedSeasons) {
                    level = previous;
                }
            }
        }

        return
            (silo.deposits[depositId].seeds * (1e18 + ((level * 1e18) / Book.MaxGrowthSeedLevel))) /
            1e20;
    }
}
