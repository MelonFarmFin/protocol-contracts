//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../interfaces/IOracle.sol";

import "../libraries/UniswapV2Library.sol";
import "../libraries/UniswapV2OracleLibrary.sol";
import "../libraries/FixedPoint.sol";

contract MelonOracle is IOracle, Ownable {
    using FixedPoint for *;

    //////////////////////////////
    // Errors                   //
    //////////////////////////////
    error MelonOracle__MustBeAdmin();
    error MelonOracle__ExpiredPriceData();
    error MelonOracle__InvalidTokenPair();
    error MelonOracle__InvalidTokenIn();
    error MelonOracle__InvalidTimeElapsed();
    error MelonOracle__MustAfterStartTime();

    //////////////////////////////
    // State Variables          //
    //////////////////////////////
    uint256 private constant PERIOD = 3600; // 1 hour
    uint256 private constant EXPIRED_DURATION = 300; // 5 minutes
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant ONE_MELON = 1e18;

    uint256 private startTime;

    AggregatorV3Interface private priceFeed;

    address public immutable pair;
    address public immutable melonToken;
    address public immutable ethToken;

    uint32 private blockTimestampLast;
    uint256 private lastPrice0Cumulative;
    uint256 private lastPrice1Cumulative;

    //////////////////////////////
    // Constructor              //
    //////////////////////////////
    constructor(
        address _priceFeed,
        address _pair,
        address _melonToken,
        address _ethToken,
        uint256 _startTime
    ) Ownable() {
        melonToken = _melonToken;
        ethToken = _ethToken;
        pair = _pair;
        priceFeed = AggregatorV3Interface(_priceFeed);
        startTime = _startTime;
    }

    ////////////////////////////////
    // External & Public Function //
    ////////////////////////////////

    function update() external override onlyOwner {
        if (startTime > block.timestamp) {
            revert MelonOracle__MustAfterStartTime();
        }

        uint32 timeElapsed = uint32(block.timestamp) - blockTimestampLast;
        if (timeElapsed < PERIOD) {
            revert MelonOracle__InvalidTimeElapsed();
        }
        (uint256 price0Cumulative, uint256 price1Cumulative, ) = UniswapV2OracleLibrary
            .currentCumulativePrices(pair);
        blockTimestampLast = uint32(block.timestamp);
        lastPrice0Cumulative = price0Cumulative;
        lastPrice1Cumulative = price1Cumulative;
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
        return getChainlinkEthPrice();
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
        uint32 timeElapsed = uint32(block.timestamp) - blockTimestampLast;
        (address token0, ) = UniswapV2Library.sortTokens(_tokenIn, _tokenOut);
        if (blockTimestampLast == 0 || timeElapsed == 0) {
            // return spot  price for first time or timeElapsed is 0
            (uint256 reserve0, uint256 reserve1) = UniswapV2OracleLibrary.currentReserve(pair);
            if (token0 == _tokenIn) {
                return computeAmountOutSpot(reserve0, reserve1, _amountIn);
            } else {
                return computeAmountOutSpot(reserve1, reserve0, _amountIn);
            }
        } else {
            (uint256 price0Cumulative, uint256 price1Cumulative, ) = UniswapV2OracleLibrary
                .currentCumulativePrices(pair);
            if (token0 == _tokenIn) {
                return
                    computeAmountOut(
                        lastPrice0Cumulative,
                        price0Cumulative,
                        timeElapsed,
                        _amountIn
                    );
            } else {
                return
                    computeAmountOut(
                        lastPrice1Cumulative,
                        price1Cumulative,
                        timeElapsed,
                        _amountIn
                    );
            }
        }
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

    function computeAmountOutSpot(
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 amountIn
    ) private pure returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * 9975;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 10000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getChainlinkEthPrice() private view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        if (EXPIRED_DURATION < block.timestamp - updatedAt) {
            revert MelonOracle__ExpiredPriceData();
        }
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }
}
