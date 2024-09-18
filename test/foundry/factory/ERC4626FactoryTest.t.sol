// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {ERC4626Factory} from "../../../contracts/factory/ERC4626Factory.sol";
import {ERC4626Vault} from "../../../contracts/factory/ERC4626Vault.sol";

contract ERC4626FactoryTest is Test {
    ERC4626Factory factory;
    MockERC20 token;

    event VaultCreated(address indexed vault, address indexed underlyingAsset, string name, string symbol);

    function setUp() public {
        factory = new ERC4626Factory();
        factory.initialize();

        token = new MockERC20("Mock Token", "MCK", 18);
    }

    function testCreateVault() public {
        address vaultAddress = factory.createERC4626Vault(address(token));

        ERC4626Vault vault = ERC4626Vault(vaultAddress);

        assertEq(vault.asset(), address(token), "Vault should use the correct asset");
        assertEq(vault.name(), "Vault MCK", "Vault name should be correct");
        assertEq(vault.symbol(), "vMCK", "Vault symbol should be correct");

        assertEq(vault.decimals(), token.decimals(), "Decimals should match the underlying token");
    }
}
