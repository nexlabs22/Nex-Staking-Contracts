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

    /// @notice Swaps a given reward token to WETH.
    /// @param uniswapRouter The Uniswap V3 router.
    /// @param rewardToken The address of the reward token to swap.
    /// @param amountIn The amount of reward token to swap.
    /// @return amountOut The amount of WETH received from the swap.
    function swapRewardToWETH(ISwapRouter uniswapRouter, address rewardToken, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "SwapHelpers: amountIn must be greater than zero");
        amountOut =
            swapTokens(uniswapRouter, rewardToken, address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), amountIn); // WETH address
    }

    /// @notice Swaps an index token to the user's chosen reward token via WETH.
    /// @param uniswapRouter The Uniswap V3 router.
    /// @param path The swap path from index token to WETH to the chosen reward token.
    /// @param amountIn The amount of index token to swap.
    /// @return amountOut The amount of reward token received from the swap.
    function swapIndexToReward(ISwapRouter uniswapRouter, address[] memory path, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "SwapHelpers: amountIn must be greater than zero");
        require(path.length >= 2, "SwapHelpers: Path must have at least two tokens");

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(path[0], uint24(3000), path[1], uint24(3000), path[2]),
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        amountOut = uniswapRouter.exactInput(params);
    }

    /// @notice Swaps WETH to an index token and distributes it between pools.
    /// @param uniswapRouter The Uniswap V3 router.
    /// @param weth The address of the WETH token.
    /// @param indexTokens The array of index tokens to swap to.
    /// @param amountsIn The array of amounts of WETH to swap for each index token.
    /// @return amountsOut The array of amounts of index tokens received from the swaps.
    function swapWETHToIndexAndDistribute(
        ISwapRouter uniswapRouter,
        address weth,
        address[] memory indexTokens,
        uint256[] memory amountsIn
    ) internal returns (uint256[] memory amountsOut) {
        require(indexTokens.length == amountsIn.length, "SwapHelpers: Mismatched array lengths");

        amountsOut = new uint256[](indexTokens.length);

        for (uint256 i = 0; i < indexTokens.length; i++) {
            require(amountsIn[i] > 0, "SwapHelpers: amountIn must be greater than zero for each token");

            amountsOut[i] = swapTokens(uniswapRouter, weth, indexTokens[i], amountsIn[i]);
        }
    }
    // function swapTokens(ISwapRouter uniswapRouter, address tokenIn, address tokenOut, uint256 amountIn)
    //     internal
    //     returns (uint256 amountOut)
    // {
    //     ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    //         tokenIn: tokenIn,
    //         tokenOut: tokenOut,
    //         fee: 3000,
    //         recipient: address(this),
    //         deadline: block.timestamp + 300,
    //         amountIn: amountIn,
    //         amountOutMinimum: 0,
    //         sqrtPriceLimitX96: 0
    //     });

    //     amountOut = uniswapRouter.exactInputSingle(params);
    // }

    // function swapTokensForTargetToken(ISwapRouter uniswapRouter, address[] memory tokens, address tokenOut, uint24 fee)
    //     internal
    // {
    //     for (uint256 i = 0; i < tokens.length; i++) {
    //         IERC20 token = IERC20(tokens[i]);
    //         uint256 tokenBalance = token.balanceOf(address(this));

    //         if (tokenBalance > 0) {
    //             token.approve(address(uniswapRouter), tokenBalance);

    //             ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    //                 tokenIn: tokens[i],
    //                 tokenOut: tokenOut,
    //                 fee: fee,
    //                 recipient: address(this),
    //                 deadline: block.timestamp + 300,
    //                 amountIn: tokenBalance,
    //                 amountOutMinimum: 0,
    //                 sqrtPriceLimitX96: 0
    //             });

    //             uniswapRouter.exactInputSingle(params);
    //         }
    //     }
    // }
}
