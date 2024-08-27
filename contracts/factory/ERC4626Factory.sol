// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4626Vault} from "./ERC4626Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC4626Factory {
    event VaultCreated(address indexed vault, address indexed underlyingAsset);

    function createERC4626Vault(address _underlyingAsset, string memory _name, string memory _symbol)
        external
        returns (address)
    {
        ERC4626Vault vault = new ERC4626Vault(IERC20(_underlyingAsset), _name, _symbol);
        emit VaultCreated(address(vault), _underlyingAsset);
        return address(vault);
    }
}
