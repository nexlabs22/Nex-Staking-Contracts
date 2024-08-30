// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {ERC4626Vault} from "./ERC4626Vault.sol";

contract ERC4626Factory is OwnableUpgradeable {
    event VaultCreated(address indexed vault, address indexed underlyingAsset, string name, string symbol);

    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    function createERC4626Vault(address _underlyingAsset) external onlyOwner returns (address) {
        require(_underlyingAsset != address(0), "Invalid underlying asset address");

        string memory symbol = ERC20(_underlyingAsset).symbol();
        string memory name = string(abi.encodePacked("Vault ", symbol));
        string memory vaultSymbol = string(abi.encodePacked("v", symbol));

        ERC4626Vault vault = new ERC4626Vault(IERC20(_underlyingAsset), name, vaultSymbol);
        emit VaultCreated(address(vault), _underlyingAsset, name, vaultSymbol);
        return address(vault);
    }
}
