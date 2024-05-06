//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// the core and only oracle of Melon
// all the return values should be in the precision of 18 decimals
// if the price is 0.1, the return value should be 0.1e18 or 1e17
interface IOracle {
    // the oracle is an implementation of Univ2-TWAP of Melon-WETH
    // this function should return the price of given _token with other
    // for example, if input _token is Melon, return the price of Melon in ETH
    // it means how many ETH per 1 Melon?
    function getAssetPrice(address _token) external view returns (uint256);

    // this function query ETH price from an external oracle service like ChainLink
    // and return the price of ETH in US Dollar
    function getEthPrice() external view returns (uint256);

    // allow only owner address can update the oracle
    // update oracle everytime this function is called no matter how much time was passed
    // the duration will be managed by the owner
    function update() external;
}
