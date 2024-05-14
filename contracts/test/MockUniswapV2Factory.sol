// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/////////////////////
/// FOR TEST ONLY ///
/////////////////////

contract MockUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair) {
        return address(1);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        return address(1);
    }
}
