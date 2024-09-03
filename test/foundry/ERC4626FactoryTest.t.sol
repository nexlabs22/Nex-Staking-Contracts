// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Test} from "forge-std/Test.sol";
// import {ERC4626Factory} from "../../contracts/factory/ERC4626Factory.sol";
// import {MockERC20} from "./mocks/MockERC20.sol";

// contract ERC4626FactoryTest is Test {
//     ERC4626Factory factory;
//     MockERC20 mockToken;

//     function setUp() public {
//         factory = new ERC4626Factory();
//         mockToken = new MockERC20("Mock Token", "MTK", 18);
//     }

//     function testCreateERC4626Vault() public {
//         address vault = factory.createERC4626Vault(address(mockToken));

//         assertTrue(vault != address(0));
//     }
// }
