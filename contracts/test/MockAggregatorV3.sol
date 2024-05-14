// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

/////////////////////
/// FOR TEST ONLY ///
/////////////////////
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Router} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Router.sol";
import {UniswapV2Factory} from "@uniswap/v2-core/contracts/UniswapV2Factory.sol";
import {UniswapV2Router} from "@uniswap/v2-core/contracts/UniswapV2Router.sol";

contract MockAggregatorV3 is AggregatorV3Interface {
    int256 private price;
    uint8 private decimal;
    uint256 private updatedAt;

    constructor(int256 _price, uint8 _decimal) {
        price = _price;
        decimal = _decimal;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) public {
        price = _price;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 _updatedAt) public {
        updatedAt = _updatedAt;
    }

    function setDecimal(uint8 _decimal) public {
        decimal = _decimal;
    }

    function decimals() external view override returns (uint8) {
        return decimal;
    }

    function description() external pure override returns (string memory) {
        return "Mock Aggregator V3";
    }

    function version() external pure override returns (uint256) {
        return 0;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, price, updatedAt, updatedAt, 0);
    }

    function getRoundData(
        uint80 _roundId
    ) external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, price, updatedAt, updatedAt, 0);
    }
}
