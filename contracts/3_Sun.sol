//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Book} from "./0_Book.sol";
import {Weather} from "./2_Weather.sol";
import {IMelon} from "./interfaces/IMelon.sol";

contract Sun is Weather {
    event Sunrise(uint256 indexed season, int256 indexed deltaSupply);
    event SupplyMinted(uint256 indexed season, uint256 indexed toSilo, uint256 indexed toField);
    event PodMinted(uint256 indexed season, uint256 indexed pods);
    event TemperatureUpdated(
        uint256 indexed season,
        uint256 indexed temperature,
        uint256 podRate,
        uint256 podDemand
    );

    error SeasonHasNotEndedYet();

    function doSunrise() internal {
        if (season.endTime > block.timestamp) {
            revert SeasonHasNotEndedYet();
        }

        // increase season number and time
        season.current = season.current + 1;
        season.endTime = block.timestamp + Book.SeasonPeriod;

        int256 deltaSupply = getSupplyDelta();

        // grow Melon supply in case positive deltaSupply
        if (deltaSupply > 0) {
            uint256 newMelons = growSupply(uint256(deltaSupply));

            // incentive transaction caller with 1% new supply
            // maximum of 100 melons
            uint256 incentiveAmount = (newMelons * 1e18) / 100e18;
            if (incentiveAmount > 100e18) {
                incentiveAmount = 100e18;
            }
            IMelon(melon).mint(msg.sender, incentiveAmount);
        } else {
            // fixed 1 melon
            IMelon(melon).mint(msg.sender, 1e18);
        }

        updateField(deltaSupply);

        emit Sunrise(season.current, deltaSupply);
    }

    function growSupply(uint256 deltaSupply) internal returns (uint256) {
        uint256 newMelons = (deltaSupply * Book.MelonSupplyGrowthRate) / 1e18;

        // mint new Melons
        IMelon(melon).mint(address(this), newMelons);

        // melons go to treasury
        uint256 newMelonsForTreasury = (newMelons * Book.MelonSupplyShareToTreasury) / 1e18;

        // the maximum Melons amount can be distributed to Field
        uint256 newMelonsForField = (newMelons * Book.MelonSupplyShareToPod) / 1e18;

        // distribute Melons to Field only when there are pods needs to be redeemed
        if (field.podRedeemable < field.podLine) {
            uint256 notRedeemable = field.podLine - field.podRedeemable;

            // distribute enough Melons for remain pod need to be redeemed
            newMelonsForField = notRedeemable > newMelonsForField
                ? newMelonsForField
                : notRedeemable;

            // update the pod redeemable line
            field.podRedeemable = field.podRedeemable + newMelonsForField;
        } else {
            // no new Melons distribute to Field
            newMelonsForField = 0;
        }

        uint256 newMelonForSilo = newMelons - newMelonsForField - newMelonsForTreasury;

        // distribute remain Melons to Silo
        silo.totalMelons = silo.totalMelons + newMelonForSilo;

        // transfer melons to treasury
        IMelon(melon).transfer(treasury, newMelonsForTreasury);

        emit SupplyMinted(season.current, newMelonForSilo, newMelonsForField);

        return newMelons;
    }

    function updateField(int256 deltaSupply) internal {
        uint256 melonSupply = IMelon(melon).totalSupply();
        if (melonSupply == 0) return;

        // podRate = (podLine - podRedeemable) / melonSupply
        uint256 podRate = (field.podLine - field.podRedeemable) / melonSupply;

        // podDemand = melonAvailable / melonStart
        uint256 podDemand;
        if (field.soilStart > 0) {
            podDemand = (field.soilAvailable * 1e18) / field.soilStart;
        }

        if (deltaSupply < 0) {
            updateFieldBelowPeg(deltaSupply, podRate, podDemand);
        } else if (deltaSupply > 0) {
            updateFieldAbovePeg(deltaSupply, podRate, podDemand);
        }

        field.soilStart = field.soilAvailable;

        emit PodMinted(season.current, field.soilAvailable);
    }

    function updateFieldBelowPeg(int256 deltaSupply, uint256 podRate, uint256 podDemand) internal {
        // below peg, new pods number always equal to deltaSupply
        field.soilAvailable = uint256(-deltaSupply);

        if (podRate < Book.PodRateOptimal) {
            // low pod rate
            if (podDemand < Book.PodDemandRateHigh) {
                // high pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateLow);
                }
            } else if (podDemand >= Book.PodDemandRateLow) {
                // low pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(true, podRate, podDemand, Book.TemperatureJumpRateMedium);
                } else {
                    updateTemperature(true, podRate, podDemand, Book.TemperatureJumpRateHigh);
                }
            } else {
                // steady pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(true, podRate, podDemand, Book.TemperatureJumpRateLow);
                } else {}
            }
        } else if (podRate > Book.PodRateOptimal) {
            // high pod rate
            if (podDemand < Book.PodDemandRateHigh) {
                // high pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateLow);
                }
            } else if (podDemand >= Book.PodDemandRateLow) {
                // low pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(true, podRate, podDemand, Book.TemperatureJumpRateMedium);
                } else {
                    updateTemperature(true, podRate, podDemand, Book.TemperatureJumpRateHigh);
                }
            } else {
                // steady pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(true, podRate, podDemand, Book.TemperatureJumpRateLow);
                } else {
                    updateTemperature(true, podRate, podDemand, Book.TemperatureJumpRateMedium);
                }
            }
        }
    }

    function updateFieldAbovePeg(int256 deltaSupply, uint256 podRate, uint256 podDemand) internal {
        if (podRate < Book.PodRateOptimal) {
            // low pod rate
            if (podDemand < Book.PodDemandRateHigh) {
                // high pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateSuper);
                } else {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateHigh);
                }
            } else if (podDemand >= Book.PodDemandRateLow) {
                // low pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateHigh);
                } else {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateLow);
                }
            } else {
                // steady pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateSuper);
                } else {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateHigh);
                }
            }

            field.soilAvailable = (uint256(deltaSupply) * Book.PodGrowthRateWhenPodRateLow) / 1e18;
        } else if (podRate > Book.PodRateOptimal) {
            // high pod rate
            if (podDemand < Book.PodDemandRateHigh) {
                // high pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateSuper);
                } else {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateHigh);
                }
            } else if (podDemand >= Book.PodDemandRateLow) {
                // low pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateLow);
                }
            } else {
                // steady pod demand
                if (field.temperature > Book.TemperatureRateOptimal) {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateHigh);
                } else {
                    updateTemperature(false, podRate, podDemand, Book.TemperatureJumpRateLow);
                }
            }

            field.soilAvailable = (uint256(deltaSupply) * Book.PodGrowthRateWhenPodRateHigh) / 1e18;
        }
    }

    function updateTemperature(
        bool increasing,
        uint256 podRate,
        uint256 podDemand,
        uint256 jumpRate
    ) internal {
        if (increasing) {
            field.temperature = field.temperature + jumpRate;
        } else {
            field.temperature = field.temperature > jumpRate ? field.temperature - jumpRate : 0;
        }

        emit TemperatureUpdated(season.current, field.temperature, podRate, podDemand);
    }
}
