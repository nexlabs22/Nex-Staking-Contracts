// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract RewardManager {
    using SafeERC20 for IERC20;

    ISwapRouter public uniswapRouter;
    IERC20 public targetToken;
    address public owner;
    address nexStaging;
    uint256 public threshold;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    constructor(address _nexStagingAddress, address _targetTokenAddress, uint256 _threshold) {
        nexStaging = _nexStagingAddress;
        targetToken = IERC20(_targetTokenAddress);
        threshold = _threshold * 10 ** 18;
        uniswapRouter = ISwapRouter(_uniswapRouter);

        owner = msg.sender;
    }

    function swapTokensForTargetToken(address[] calldata tokens, uint24 fee) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 tokenBalance = token.balanceOf(address(this));

            if (tokenBalance > 0) {
                require(token.approve(address(uniswapRouter), tokenBalance), "Approval failed");

                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokens[i],
                    tokenOut: targetToken,
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

    function checkAndTransfer() public {
        uint256 balance = targetToken.balanceOf(address(this));
        require(balance >= threshold, "Balance is below the threshold");
        targetToken.safeTransfer(nexStaging, balance);
    }
}
