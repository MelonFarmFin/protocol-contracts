//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMelon is IERC20 {
    function mint(address recipient, uint256 amount) external;
    function burn(address owner, uint256 amount) external;
}
