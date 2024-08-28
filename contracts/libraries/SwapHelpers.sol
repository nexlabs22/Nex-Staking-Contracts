// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {NexStaging} from "../NexStaging.sol";

library SwapHelpers {
    function swapTokensForPoolIndexToken(
        ISwapRouter uniswapRouter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee
    ) internal returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = uniswapRouter.exactInputSingle(params);
        return amountOut;
    }

    // function swapTokensForPoolIndexToken(ISwapRouter uniswapRouter, uint256 ethAmount, address tokenOut, uint24 fee)
    //     internal
    //     returns (uint256)
    // {
    //     ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    //         tokenIn: address(0), // Use WETH instead of ETH
    //         tokenOut: tokenOut,
    //         fee: fee,
    //         recipient: address(this),
    //         deadline: block.timestamp + 300,
    //         amountIn: ethAmount,
    //         amountOutMinimum: 0,
    //         sqrtPriceLimitX96: 0
    //     });

    //     uint256 amountOut = uniswapRouter.exactInputSingle{value: ethAmount}(params);
    //     return amountOut;
    // }

    function swapIndexTokensForRewardToken(ISwapRouter uniswapRouter, address tokenIn, address tokenOut, uint256 amount)
        internal
        returns (uint256)
    {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = uniswapRouter.exactInputSingle(params);
        return amountOut;
    }

    function swapTokensForTargetToken(ISwapRouter uniswapRouter, address[] memory tokens, address tokenOut, uint24 fee)
        internal
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 tokenBalance = token.balanceOf(address(this));

            if (tokenBalance > 0) {
                token.approve(address(uniswapRouter), tokenBalance);

                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokens[i],
                    tokenOut: tokenOut,
                    fee: fee,
                    recipient: address(this),
                    deadline: block.timestamp + 300,
                    amountIn: tokenBalance,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });

                uniswapRouter.exactInputSingle(params);
            }
        }
    }
}
