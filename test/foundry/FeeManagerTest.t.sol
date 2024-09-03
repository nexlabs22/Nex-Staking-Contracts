// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Test} from "forge-std/Test.sol";
// import {FeeManager} from "../../contracts/FeeManager.sol";
// import {MockERC20} from "./mocks/MockERC20.sol";
// import {NexStaking} from "../../contracts/NexStaking.sol";
// import {IWETH9} from "../../contracts/interfaces/IWETH9.sol";

// contract FeeManagerTest is Test {
//     FeeManager feeManager;
//     NexStaking nexStaking;
//     MockERC20 usdc;
//     IWETH9 weth;

//     function setUp() public {
//         weth = IWETH9(address(new MockERC20("Wrapped Ether", "WETH", 18)));
//         usdc = new MockERC20("USD Coin", "USDC", 6);

//         nexStaking = new NexStaking();
//         feeManager = new FeeManager();

//         address[] memory rewardTokens;
//         rewardTokens = new address[](1);
//         rewardTokens[0] = address(usdc);

//         feeManager.initialize(
//             nexStaking,
//             rewardTokens,
//             0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E, // Uniswap V3 Router Address
//             0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E, // Uniswap V2 Router Address
//             address(weth),
//             address(usdc),
//             1000
//         );
//     }

//     function testCheckAndTransfer() public {
//         uint256 initialBalance = 1e18;

//         weth.deposit{value: initialBalance}();
//         weth.transfer(address(feeManager), initialBalance);

//         feeManager.checkAndTransfer();

//         uint256 finalWethBalance = weth.balanceOf(address(feeManager));
//         uint256 finalUsdcBalance = usdc.balanceOf(address(this));

//         assertLt(finalWethBalance, initialBalance);
//         assertGt(finalUsdcBalance, 0);
//     }
// }
