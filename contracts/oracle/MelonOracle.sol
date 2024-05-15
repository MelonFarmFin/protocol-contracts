//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {PrimaryProdDataServiceConsumerBase} from "@redstone-finance/evm-connector/contracts/data-services/PrimaryProdDataServiceConsumerBase.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/uniswap/IUniswapV2Pair.sol";

import "../libraries/UniswapV2Library.sol";
import "../libraries/UniswapV2OracleLibrary.sol";
import "../libraries/FixedPoint.sol";

contract MelonOracle is PrimaryProdDataServiceConsumerBase, IOracle {
    using FixedPoint for *;

    //////////////////////////////
    // Errors                   //
    //////////////////////////////
    error MelonOracle__MustBeAdmin();
    error MelonOracle__NoAvailablePriceFeed();
    error MelonOracle__GranularityMustGreaterThanOne();
    error MelonOracle__WindowSizeMustBeEvenlyDivisible();
    error MelonOracle__InvalidTokenPair();
    error MelonOracle__InvalidTokenIn();
    error MelonOracle__MissingHistoricalData();
    error MelonOracle__InvalidTimeElapsed();
    error MelonOracle__MustAfterStartTime();

    //////////////////////////////
    // Structs                  //
    //////////////////////////////
    struct Observation {
        uint32 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    //////////////////////////////
    // State Variables          //
    //////////////////////////////
    uint256 private constant EXPIRED_DURATION = 300; // 5 minutes
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant ONE_MELON = 1e18;

    address private admin;

    uint256 private startTime;

    AggregatorV3Interface private priceFeed;

    uint8 public immutable granularity;
    uint32 public immutable windowSize;
    uint32 public immutable periodSize;

    address public immutable pair;
    address public immutable melonToken;
    address public immutable ethToken;

    Observation[] public pairObservations;

    //////////////////////////////
    // Modifiers                //
    //////////////////////////////
    modifier onlyAdmin(address _sender) {
        if (_sender != admin) {
            revert MelonOracle__MustBeAdmin();
        }
        _;
    }

    //////////////////////////////
    // Constructor              //
    //////////////////////////////
    constructor(
        address _admin,
        address _priceFeed,
        address _pair,
        address _melonToken,
        address _ethToken,
        uint32 _windowSize,
        uint8 _granularity,
        uint256 _startTime
    ) {
        if (_granularity <= 1) {
            revert MelonOracle__GranularityMustGreaterThanOne();
        }
        if ((periodSize = _windowSize / _granularity) * _granularity != _windowSize) {
            revert MelonOracle__WindowSizeMustBeEvenlyDivisible();
        }

        melonToken = _melonToken;
        ethToken = _ethToken;
        pair = _pair;
        windowSize = _windowSize;
        granularity = _granularity;
        priceFeed = AggregatorV3Interface(_priceFeed);
        admin = _admin;
        startTime = _startTime;
    }

    ////////////////////////////////
    // External & Public Function //
    ////////////////////////////////
    function getAdmin() external view returns (address) {
        return admin;
    }

    function update() external override onlyAdmin(msg.sender) {
        if (startTime > block.timestamp) {
            revert MelonOracle__MustAfterStartTime();
        }
        for (uint8 i = uint8(pairObservations.length); i < granularity; i++) {
            pairObservations.push();
        }
        uint8 observationIndex = observationIndexOf(uint32(block.timestamp));
        Observation storage observation = pairObservations[observationIndex];

        uint32 timeElapsed = uint32(block.timestamp) - observation.timestamp;
        if (timeElapsed > periodSize) {
            (uint256 price0Cumulative, uint256 price1Cumulative, ) = UniswapV2OracleLibrary
                .currentCumulativePrices(pair);
            observation.timestamp = uint32(block.timestamp);
            observation.price0Cumulative = price0Cumulative;
            observation.price1Cumulative = price1Cumulative;
        }
    }

    function getAssetPrice(address _token) external view override returns (uint256) {
        if (startTime > block.timestamp) {
            return 0;
        }
        if (_token != melonToken && _token != ethToken) {
            revert MelonOracle__InvalidTokenIn();
        }
        return consult(_token, ONE_MELON);
    }

    function getEthPrice() public view override returns (uint256) {
        if (startTime > block.timestamp) {
            return 0;
        }
        (bool chainlinkPriceAvailable, uint256 chainlinkEthPrice) = getChainlinkEthPrice();
        if (chainlinkPriceAvailable) {
            return chainlinkEthPrice;
        }
        uint256 redstoneEthPrice = getRedstoneEthPrice();
        return redstoneEthPrice;
    }

    function getMelonUsdPrice() external view returns (uint256) {
        if (startTime > block.timestamp) {
            return 0;
        }
        uint256 melonEthPrice = consult(melonToken, ONE_MELON);
        uint256 ethUsdPrice = getEthPrice();
        return (melonEthPrice * ethUsdPrice) / PRECISION;
    }

    function consult(address _tokenIn, uint256 _amountIn) public view returns (uint256) {
        if (startTime > block.timestamp) {
            return 0;
        }
        if (_tokenIn != melonToken && _tokenIn != ethToken) {
            revert MelonOracle__InvalidTokenIn();
        }
        address _tokenOut = _tokenIn == melonToken ? ethToken : melonToken;
        Observation storage firstObservation = getFirstObservationInWindow();

        uint32 timeElapsed = uint32(block.timestamp) - firstObservation.timestamp;
        if (timeElapsed > windowSize) {
            revert MelonOracle__MissingHistoricalData();
        }
        if (timeElapsed < windowSize - periodSize * 2) {
            revert MelonOracle__InvalidTimeElapsed();
        }

        (uint256 price0Cumulative, uint256 price1Cumulative, ) = UniswapV2OracleLibrary
            .currentCumulativePrices(pair);
        (address token0, ) = UniswapV2Library.sortTokens(_tokenIn, _tokenOut);

        if (token0 == _tokenIn) {
            return
                computeAmountOut(
                    firstObservation.price0Cumulative,
                    price0Cumulative,
                    timeElapsed,
                    _amountIn
                );
        } else {
            return
                computeAmountOut(
                    firstObservation.price1Cumulative,
                    price1Cumulative,
                    timeElapsed,
                    _amountIn
                );
        }
    }

    function observationIndexOf(uint32 _timestamp) public view returns (uint8) {
        uint32 epochPeriod = _timestamp / periodSize;
        return uint8(epochPeriod % granularity);
    }

    /////////////////////////////////
    // Internal & Private Function //
    /////////////////////////////////

    function computeAmountOut(
        uint256 priceCumulativeStart,
        uint256 priceCumulativeEnd,
        uint32 timeElapsed,
        uint256 amountIn
    ) private pure returns (uint256 amountOut) {
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
        );
        amountOut = priceAverage.mul(amountIn).decode144();
    }

    function getFirstObservationInWindow()
        private
        view
        returns (Observation storage firstObservation)
    {
        uint8 observationIndex = observationIndexOf(uint32(block.timestamp));
        uint8 firstObservationIndex = (observationIndex + 1) % granularity;
        firstObservation = pairObservations[firstObservationIndex];
    }

    function getChainlinkEthPrice() private view returns (bool, uint256) {
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        if (EXPIRED_DURATION < block.timestamp - updatedAt) {
            return (false, 0);
        }
        return (true, (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getRedstoneEthPrice() private view returns (uint256 ethPrice) {
        ethPrice = getOracleNumericValueFromTxMsg(bytes32("ETH")) * ADDITIONAL_FEED_PRECISION;
    }
}
