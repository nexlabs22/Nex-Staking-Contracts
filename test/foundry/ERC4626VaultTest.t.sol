// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import "forge-std/Test.sol";
// import {ERC4626Vault} from "../../contracts/factory/ERC4626Vault.sol";
// import {MockERC20} from "./mocks/MockERC20.sol";

// contract ERC4626VaultTest is Test {
//     ERC4626Vault vault;
//     MockERC20 mockToken;

//     function setUp() public {
//         mockToken = new MockERC20("Mock Token", "MTK", 18);
//         vault = new ERC4626Vault(mockToken, "Vault Mock Token", "vMTK");
//     }

//     function testDepositAndMint() public {
//         uint256 depositAmount = 1e18;

//         mockToken.mint(address(this), depositAmount);
//         mockToken.approve(address(vault), depositAmount);

//         vault.deposit(depositAmount, address(this));

//         uint256 shares = vault.balanceOf(address(this));
//         assertEq(shares, depositAmount);
//     }
// }
