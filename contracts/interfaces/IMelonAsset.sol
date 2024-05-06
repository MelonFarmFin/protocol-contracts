//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMelonAsset is IERC721 {
    function mint(address _owner, uint256 _tokenId) external;
    function burn(uint256 _tokenId) external;
}
