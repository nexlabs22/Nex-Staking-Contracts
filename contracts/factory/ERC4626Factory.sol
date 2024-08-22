// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/interfaces/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract ERC4626Factory is ERC4626 {
    constructor(ERC20 asset, string memory _name, string memory _symbol) ERC4626(asset) {}
}
