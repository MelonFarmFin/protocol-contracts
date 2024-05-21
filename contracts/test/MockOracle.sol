// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IOracle} from "../interfaces/IOracle.sol";

/////////////////////
/// FOR TEST ONLY ///
/////////////////////

contract MockOracle is IOracle {
    uint256 private assetPrice;
    address private ethPriceFeed;

    constructor(address _ethPriceFeed) {
        ethPriceFeed = _ethPriceFeed;
    }

    function setAssetPrice(uint256 _assetPrice) external {
        assetPrice = _assetPrice;
    }

    function update() external {}

    function getAssetPrice(address) public view returns (uint256) {
        return assetPrice;
    }

    function getEthPrice() public view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(ethPriceFeed).latestRoundData();

        return uint256(price) * 1e10;
    }
}
