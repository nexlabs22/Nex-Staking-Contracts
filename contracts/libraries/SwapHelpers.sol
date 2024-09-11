// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";

library SwapHelpers {
    function swapTokens(ISwapRouter uniswapRouter, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        IERC20(tokenIn).approve(address(uniswapRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        amountOut = uniswapRouter.exactInputSingle(params);
    }

    function swapIndexToReward(ISwapRouter uniswapRouter, address[] memory path, uint256 amountIn, address recipient)
        internal
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "SwapHelpers: amountIn must be greater than zero");
        require(path.length >= 2, "SwapHelpers: Path must have at least two tokens");

        IERC20(path[0]).approve(address(uniswapRouter), amountIn);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(path[0], uint24(3000), path[1], uint24(3000), path[2]),
            // path: path,
            recipient: recipient,
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        amountOut = uniswapRouter.exactInput(params);
    }
}
