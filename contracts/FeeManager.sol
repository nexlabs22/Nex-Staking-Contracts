// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {NexStaging} from "./NexStaging.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract RewardManager {
    using SafeERC20 for IERC20;

    NexStaging public nexStaging;
    // IERC20 public targetToken;
    ISwapRouter public uniswapRouter;
    IWETH9 weth;

    address public owner;
    uint256 private threshold;
    // address private nexStaging;
    address[] private rewardTokensAddresses;

    enum RouterVersion {
        ROUTER_V3,
        ROUTER_V2
    }

    event TransferTokens(uint256 indexed amount, uint256 indexed timestamp);

    constructor(
        NexStaging _nexStagingAddress,
        // address _targetTokenAddress,
        address[] memory _rewardTokensAddresses,
        address _uniswapRouter,
        uint256 _threshold,
        address _weth
    ) {
        nexStaging = NexStaging(_nexStagingAddress);
        // targetToken = IERC20(_targetTokenAddress);
        threshold = _threshold * 10 ** 18;
        uniswapRouter = ISwapRouter(_uniswapRouter);
        owner = msg.sender;
        weth = IWETH9(_weth);

        for (uint256 i = 0; i < _rewardTokensAddresses.length; i++) {
            rewardTokensAddresses.push(_rewardTokensAddresses[i]);
        }
    }

    function swapTokensForTargetToken(address[] memory tokens, uint24 fee) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 tokenBalance = token.balanceOf(address(this));

            if (tokenBalance > 0) {
                token.approve(address(uniswapRouter), tokenBalance);

                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokens[i],
                    tokenOut: address(weth),
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
        swapTokensForTargetToken(rewardTokensAddresses, 3000);
        uint256 wethBalance = weth.balanceOf(address(this));
        weth.withdraw(wethBalance);
        uint256 balance = getBalance();
        // uint256 balance = targetToken.balanceOf(address(this));
        require(balance >= threshold, "Balance is below the threshold");
        (bool sent,) = address(nexStaging).call{value: balance}("");
        require(sent, "Failed to send Ether");
        // targetToken.safeTransfer(address(nexStaging), balance);
        emit TransferTokens(balance, block.timestamp);
    }

    function getBalance() internal view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {}

    fallback() external payable {}

    // function swapTokensForTargetToken(address[] memory tokens, uint24 fee) internal {
    //     for (uint256 i = 0; i < tokens.length; i++) {
    //         IERC20 token = IERC20(tokens[i]);
    //         uint256 tokenBalance = token.balanceOf(address(this));

    //         if (tokenBalance > 0) {
    //             require(token.approve(address(uniswapRouter), tokenBalance), "Approval failed");

    //             ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    //                 tokenIn: tokens[i],
    //                 tokenOut: address(targetToken),
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

    // function checkAndTransfer() public {
    //     swapTokensForTargetToken(rewardTokensAddresses, 100);
    //     uint256 balance = targetToken.balanceOf(address(this));
    //     require(balance >= threshold, "Balance is below the threshold");
    //     targetToken.safeTransfer(address(nexStaging), balance);

    //     emit TrasferTokens(balance, block.timestamp);
    // }
}
