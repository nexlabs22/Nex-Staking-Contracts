// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {NexStaking} from "./NexStaking.sol";
import {SwapHelpers} from "./libraries/SwapHelpers.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract FeeManager is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    NexStaking public nexStaking;
    ISwapRouter public uniswapRouter;
    IWETH9 public weth;
    IERC20 public usdc;

    uint256 private threshold;
    address[] private rewardTokensAddresses;

    event TokensSwapped(address indexed token, uint256 amountIn, uint256 amountOut);
    event TransferToStaging(uint256 amount, uint256 timestamp);
    event TransferToOwner(uint256 amount, uint256 timestamp);

    function initialize(
        NexStaking _nexStagingAddress,
        address[] memory _rewardTokensAddresses,
        address _uniswapRouter,
        address _weth,
        address _usdc,
        uint256 _threshold
    ) public initializer {
        __Ownable_init(msg.sender);

        nexStaking = NexStaking(_nexStagingAddress);
        uniswapRouter = ISwapRouter(_uniswapRouter);
        weth = IWETH9(_weth);
        usdc = IERC20(_usdc);
        threshold = _threshold * 10 ** 18;

        for (uint256 i = 0; i < _rewardTokensAddresses.length; i++) {
            rewardTokensAddresses.push(_rewardTokensAddresses[i]);
        }
    }

    function checkAndTransfer() external {
        SwapHelpers.swapTokensForTargetToken(uniswapRouter, rewardTokensAddresses, address(weth), 3000);

        uint256 wethBalance = weth.balanceOf(address(this));
        require(wethBalance >= threshold, "WETH balance is below the threshold");

        // Split the WETH balance
        uint256 wethForStaging = wethBalance / 2;
        uint256 wethForOwner = wethBalance - wethForStaging;

        // Withdraw half of WETH to get ETH and transfer to NexStaging
        weth.withdraw(wethForStaging);
        (bool stagingTransferSuccess,) = address(nexStaking).call{value: wethForStaging}("");
        require(stagingTransferSuccess, "Failed to transfer ETH to NexStaging contract");
        emit TransferToStaging(wethForStaging, block.timestamp);

        // Swap the remaining WETH to USDC (or another token for owner)
        uint256 usdcAmount = SwapHelpers.swapTokens(uniswapRouter, address(weth), address(usdc), wethForOwner);

        // Transfer USDC (or another token) to the contract owner
        usdc.safeTransfer(owner(), usdcAmount);
        emit TransferToOwner(usdcAmount, block.timestamp);
    }

    receive() external payable {}

    fallback() external payable {}
}
