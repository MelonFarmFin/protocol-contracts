//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Book holds all configs and parameters of MelonFarm
library Book {
    // the season period in seconds
    uint internal constant SeasonPeriod = 1 hours;

    // can be withdrawn after 8 seasons only
    uint internal constant SeasonDepositLocked = 8;

    // fixed sunrise rewards
    uint256 internal constant SeasonSunriseIncentiveMin = 1e18;
    uint256 internal constant SeasonSunriseIncentiveMax = 10e18;

    // maximum growth seed ratio level
    uint internal constant MaxGrowthSeedLevel = 10496;

    // if the weather is rainy, we don't mint full deltaSupply amount
    // we just mint MelonSupplyGrowthRate of deltaSupply
    uint internal constant MelonSupplyGrowthRate = 618e15; // 61.8%

    // 40% new supply go to Field
    uint internal constant MelonSupplyShareToPod = 40e16; // 40%
    // 10% new supply go to treasury
    uint internal constant MelonSupplyShareToTreasury = 10e16; // 10%

    // the maximum seed growth multiplier that an address can archive
    uint internal constant SeedGrowthMultiplierMax = 10946; // 10946 seasons ~ 457 days

    // total level of seed growth multiplier
    uint internal constant SeedGrowthMultiplierLevels = 20;

    // the optimal pod rate
    uint internal constant PodRateOptimal = 15e16; // 15%

    // the pod demand rates
    uint internal constant PodDemandRateHigh = 1e17; // 10% remain Pods - demand increasing
    uint internal constant PodDemandRateLow = 5e17; // 50% remain Pods - demand decreasing

    // in case Melon price is above peg
    // we mint new pods following these rates
    uint internal constant PodGrowthRateWhenPodRateLow = 1e16; // 1% new Melon supply
    uint internal constant PodGrowthRateWhenPodRateHigh = 0.5e16; // 0.5% new Melon supply

    // temperature rates
    uint internal constant TemperatureRateBoostrap = 6e17; // 60%
    uint internal constant TemperatureRateOptimal = 1e18; // 100%

    // temperature jump rates
    uint internal constant TemperatureJumpRateLow = 0.5e16; // 0.5%
    uint internal constant TemperatureJumpRateMedium = 1e16; // 1%
    uint internal constant TemperatureJumpRateHigh = 3e16; // 3%
    uint internal constant TemperatureJumpRateSuper = 6e16; // 6%

    // addresses
    address internal constant ChainlinkPriceFeedEthBaseTestnet =
        0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    address internal constant UniswapV2FactoryBaseTestnet =
        0x02a84c1b3BBD7401a5f7fa98a384EBC70bB5749E; // pancakeswap
    address internal constant WrappedEtherBaseTestnet = 0x4200000000000000000000000000000000000006;

    function getChainlinkPriceFeedEth(string memory network) internal pure returns (address) {
        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("BaseTestnet"))) {
            return ChainlinkPriceFeedEthBaseTestnet;
        }

        return address(0);
    }

    function getUniswapV2Factory(string memory network) internal pure returns (address) {
        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("BaseTestnet"))) {
            return UniswapV2FactoryBaseTestnet;
        }

        return address(0);
    }

    function getWrappedEther(string memory network) internal pure returns (address) {
        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("BaseTestnet"))) {
            return WrappedEtherBaseTestnet;
        }

        return address(0);
    }
}
