//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Melon is Ownable, ERC20 {
    constructor() Ownable() ERC20("Melon Stablecoin", "Melon") {}

    // the only minter is the Farm contract
    function mint(address _recipient, uint256 _amount) external onlyOwner {
        _mint(_recipient, _amount);
    }

    // only owner (the Farm) can burn token
    function burn(address _owner, uint256 _amount) external onlyOwner {
        _burn(_owner, _amount);
    }
}
