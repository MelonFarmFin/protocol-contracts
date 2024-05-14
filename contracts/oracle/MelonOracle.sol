//SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {PrimaryProdDataServiceConsumerBase} from "@redstone-finance/evm-connector/contracts/data-services/PrimaryProdDataServiceConsumerBase.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/libraries/UniswapV2Library.sol";

import "../libraries/UniswapV2OracleLibrary.sol";
import "../libraries/FixedPoint.sol";

contract MelonOracle is PrimaryProdDataServiceConsumerBase {
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
    address public immutable PAIR;
    address public immutable MELON_TOKEN;
    address public immutable ETH_TOKEN;
    uint32 public immutable WINDOWSIZE;
    uint8 public immutable GRANULARITY;
    uint32 public immutable PERIODSIZE;

    AggregatorV3Interface private priceFeed;
    address private admin;
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
        address _factory,
        address _melonToken,
        address _ethToken,
        uint32 _windowSize,
        uint8 _granularity
    ) {
        if (_granularity <= 1) {
            revert MelonOracle__GranularityMustGreaterThanOne();
        }
        if ((PERIODSIZE = _windowSize / _granularity) * _granularity != _windowSize) {
            revert MelonOracle__WindowSizeMustBeEvenlyDivisible();
        }

        address _pair = IUniswapV2Factory(_factory).getPair(_ethToken, _melonToken);
        if (_pair == address(0)) {
            revert MelonOracle__InvalidTokenPair();
        }
        MELON_TOKEN = _melonToken;
        ETH_TOKEN = _ethToken;
        PAIR = _pair;
        WINDOWSIZE = _windowSize;
        GRANULARITY = _granularity;
        priceFeed = AggregatorV3Interface(_priceFeed);
        admin = _admin;
    }

    ////////////////////////////////
    // External & Public Function //
    ////////////////////////////////
    function getAdmin() external view returns (address) {
        return admin;
    }

    function update() external onlyAdmin(msg.sender) {
        for (uint8 i = uint8(pairObservations.length); i < GRANULARITY; i++) {
            pairObservations.push();
        }
        uint8 observationIndex = observationIndexOf(uint32(block.timestamp));
        Observation storage observation = pairObservations[observationIndex];

        uint32 timeElapsed = uint32(block.timestamp) - observation.timestamp;
        if (timeElapsed > PERIODSIZE) {
            (uint256 price0Cumulative, uint256 price1Cumulative, ) = UniswapV2OracleLibrary
                .currentCumulativePrices(PAIR);
            observation.timestamp = uint32(block.timestamp);
            observation.price0Cumulative = price0Cumulative;
            observation.price1Cumulative = price1Cumulative;
        }
    }

    function getMelonUsdPrice() external view returns (uint256) {
        uint256 melonEthPrice = consult(MELON_TOKEN, ONE_MELON);
        uint256 ethUsdPrice = getEthPrice();
        return (melonEthPrice * ethUsdPrice) / PRECISION;
    }

    function consult(address _tokenIn, uint256 _amountIn) public view returns (uint256) {
        if (_tokenIn != MELON_TOKEN && _tokenIn != ETH_TOKEN) {
            revert MelonOracle__InvalidTokenIn();
        }
        address _tokenOut = _tokenIn == MELON_TOKEN ? ETH_TOKEN : MELON_TOKEN;
        Observation storage firstObservation = getFirstObservationInWindow();

        uint32 timeElapsed = uint32(block.timestamp) - firstObservation.timestamp;
        if (timeElapsed > WINDOWSIZE) {
            revert MelonOracle__MissingHistoricalData();
        }
        if (timeElapsed < WINDOWSIZE - PERIODSIZE * 2) {
            revert MelonOracle__InvalidTimeElapsed();
        }

        (uint256 price0Cumulative, uint256 price1Cumulative, ) = UniswapV2OracleLibrary
            .currentCumulativePrices(PAIR);
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
        uint32 epochPeriod = _timestamp / PERIODSIZE;
        return uint8(epochPeriod % GRANULARITY);
    }

    function getEthPrice() public view returns (uint256) {
        (bool chainlinkPriceAvailable, uint256 chainlinkEthPrice) = getChainlinkEthPrice();
        if (chainlinkPriceAvailable) {
            return chainlinkEthPrice;
        }
        uint256 redstoneEthPrice = getRedstoneEthPrice();
        return redstoneEthPrice;
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
        uint8 firstObservationIndex = (observationIndex + 1) % GRANULARITY;
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
