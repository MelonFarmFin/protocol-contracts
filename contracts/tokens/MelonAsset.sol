//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract MelonAsset is Ownable, ERC721Enumerable {
    constructor(
        string memory name,
        string memory symbol
    ) Ownable(msg.sender) ERC721(name, symbol) {}

    function mint(address _owner, uint256 _tokenId) external onlyOwner {
        _mint(_owner, _tokenId);
    }

    function burn(uint256 _tokenId) external onlyOwner {
        _burn(_tokenId);
    }
}
