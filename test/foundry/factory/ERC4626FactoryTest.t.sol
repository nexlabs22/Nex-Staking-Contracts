// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {ERC4626Factory} from "../../../contracts/factory/ERC4626Factory.sol";
import {ERC4626Vault} from "../../../contracts/factory/ERC4626Vault.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract ERC4626FactoryTest is Test {
    ERC4626Factory factory;
    MockERC20 token;

    MockERC20[] indexTokens;

    address owner = address(10);

    event VaultCreated(address indexed vault, address indexed underlyingAsset, string name, string symbol);

    function setUp() public {
        factory = new ERC4626Factory();

        deployTokens();

        MockERC20[] memory tokens = new MockERC20[](indexTokens.length);
        for (uint256 i = 0; i < indexTokens.length; i++) {
            tokens[i] = indexTokens[i];
        }

        vm.startPrank(owner);
        factory.initialize(addressArray(tokens));

        assertEq(factory.owner(), owner, "Owner is not set correctly");

        vm.stopPrank();

        token = new MockERC20("Mock Token", "MCK");
    }

    function testCreateVault() public {
        vm.startPrank(owner);

        assertEq(factory.owner(), owner, "Factory owner is not set to owner");

        vm.recordLogs();

        address vaultAddress = factory.createERC4626Vault(address(token));

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bool foundEvent = false;
        bytes32 eventSignature = keccak256("VaultCreated(address,address,string,string)");
        for (uint256 i = 0; i < entries.length; i++) {
            Vm.Log memory logEntry = entries[i];
            if (logEntry.topics[0] == eventSignature) {
                foundEvent = true;
                address emittedVault = address(uint160(uint256(logEntry.topics[1])));
                address emittedUnderlyingAsset = address(uint160(uint256(logEntry.topics[2])));
                assertEq(emittedVault, vaultAddress, "Vault address in event mismatch");
                assertEq(emittedUnderlyingAsset, address(token), "Underlying asset in event mismatch");
                break;
            }
        }
        assertTrue(foundEvent, "VaultCreated event was not emitted");

        ERC4626Vault vault = ERC4626Vault(vaultAddress);

        string memory expectedName = string(abi.encodePacked("Vault ", token.symbol()));
        string memory expectedSymbol = string(abi.encodePacked("v", token.symbol()));

        assertEq(vault.asset(), address(token), "Vault should use the correct asset");
        assertEq(vault.name(), expectedName, "Vault name should be correct");
        assertEq(vault.symbol(), expectedSymbol, "Vault symbol should be correct");

        assertEq(vault.decimals(), token.decimals(), "Decimals should match the underlying token");

        assertEq(
            factory.tokenAddressToVaultAddress(address(token)), vaultAddress, "Vault address mapping should be updated"
        );

        vm.stopPrank();
    }

    function testCreateVaultNonOwnerReverts() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(1)));
        factory.createERC4626Vault(address(token));
    }

    function testCreateVaultInvalidUnderlyingAsset() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid underlying asset address");
        factory.createERC4626Vault(address(0));
        vm.stopPrank();
    }

    function deployTokens() public {
        for (uint256 i = 0; i < 3; i++) {
            MockERC20 indexToken = new MockERC20(
                string(abi.encodePacked("Index Token ", uint8(i + 1))), string(abi.encodePacked("IDX", uint8(i + 1)))
            );
            indexTokens.push(indexToken);

            indexToken.mint(address(this), 100000e24);
            indexToken.mint(address(this), 100000e24);
            indexToken.mint(msg.sender, 100000e24);
            indexToken.mint(msg.sender, 100000e24);
        }
    }

    function addressArray(MockERC20[] memory tokens) internal pure returns (address[] memory) {
        address[] memory addresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            addresses[i] = address(tokens[i]);
        }
        return addresses;
    }
}
