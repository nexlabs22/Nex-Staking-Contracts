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
    // function swapTokensForTargetToken(
    //     ISwapRouter uniswapRouter,
    //     IUniswapV2Router02 swapRouterV2,
    //     address[] memory tokens,
    //     address targetToken,
    //     uint24 fee,
    //     uint8 swapVersion
    // ) internal {
    //     for (uint256 i = 0; i < tokens.length; i++) {
    //         IERC20 token = IERC20(tokens[i]);
    //         uint256 tokenBalance = token.balanceOf(address(this));

    //         if (tokenBalance > 0) {
    //             if (swapVersion == 3) {
    //                 token.approve(address(uniswapRouter), tokenBalance);

    //                 ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    //                     tokenIn: tokens[i],
    //                     tokenOut: targetToken,
    //                     fee: fee,
    //                     recipient: address(this),
    //                     deadline: block.timestamp + 300,
    //                     amountIn: tokenBalance,
    //                     amountOutMinimum: 0,
    //                     sqrtPriceLimitX96: 0
    //                 });

    //                 uniswapRouter.exactInputSingle(params);
    //             } else {
    //                 address memory path;
    //                 path = new address[](2);
    //                 path[0] = tokens[i];
    //                 path[1] = targetToken;

    //                 token.approve(address(swapRouterV2), tokenBalance);

    //                 swapRouterV2.swapExactTokensForTokensSupportingFeeOnTransferTokens({
    //                     amountIn: tokenBalance,
    //                     amountOutMin: 0,
    //                     path: path,
    //                     to: address(this),
    //                     deadline: block.timestamp
    //                 });
    //             }
    //         }
    //     }
    // }

    // function swapTokens(
    //     ISwapRouter uniswapRouter,
    //     IUniswapV2Router02 swapRouterV2,
    //     address tokenIn,
    //     address tokenOut,
    //     uint256 amountIn,
    //     address recipient,
    //     uint8 swapVersion
    // ) internal returns (uint256 amountOut) {
    //     if (swapVersion == 3) {
    //         IERC20(tokenIn).approve(address(uniswapRouter), amountIn);

    //         ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    //             tokenIn: tokenIn,
    //             tokenOut: tokenOut,
    //             fee: 3000, // Assuming a 0.3% pool fee. Adjust as necessary.
    //             recipient: recipient,
    //             deadline: block.timestamp + 300,
    //             amountIn: amountIn,
    //             amountOutMinimum: 0,
    //             sqrtPriceLimitX96: 0
    //         });

    //         amountOut = uniswapRouter.exactInputSingle(params);
    //     } else {
    //         address memory path;
    //         path = new address[](2);
    //         path[0] = tokenIn;
    //         path[1] = tokenOut;

    //         IERC20(tokenIn).approve(address(swapRouterV2), amountIn);

    //         uint256[] memory amounts = swapRouterV2.swapExactTokensForTokensSupportingFeeOnTransferTokens({
    //             amountIn: amountIn,
    //             amountOutMin: 0,
    //             path: path,
    //             to: recipient,
    //             deadline: block.timestamp
    //         });

    //         amountOut = amounts[amounts.length - 1];
    //     }
    // }
}
