// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Concrete implementation of the ERC4626 Vault
contract ERC4626Vault is ERC4626 {
    constructor(IERC20 _asset) ERC4626(_asset) ERC20("ERC4626 Vault Token", "vTOKEN") {
        // Any additional initialization can go here
    }
}
