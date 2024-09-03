// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Test} from "forge-std/Test.sol";
// import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// import {SwapHelpers} from "../../contracts/libraries/SwapHelpers.sol";
// import {MockERC20} from "./mocks/MockERC20.sol";

// contract SwapHelpersTest is Test {
//     MockERC20 tokenA;
//     MockERC20 tokenB;
//     ISwapRouter swapRouter;

//     function setUp() public {
//         tokenA = new MockERC20("Token A", "TKA", 18);
//         tokenB = new MockERC20("Token B", "TKB", 18);
//         swapRouter = ISwapRouter(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);
//     }

//     function testSwapTokens() public {
//         uint256 amountIn = 1e18;

//         tokenA.mint(address(this), amountIn);
//         tokenA.approve(address(swapRouter), amountIn);

//         uint256 amountOut = SwapHelpers.swapTokens(swapRouter, address(tokenA), address(tokenB), amountIn);

//         assertGt(amountOut, 0);
//     }
// }
