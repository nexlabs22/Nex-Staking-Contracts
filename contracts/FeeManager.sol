// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {NexStaking} from "./NexStaking.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {SwapHelpers} from "./libraries/SwapHelpers.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

contract FeeManager is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    NexStaking public nexStaking;
    ISwapRouter public uniswapRouter;
    IUniswapV2Router02 public uniswapV2Router;
    IWETH9 public weth;
    IERC20 public usdc;

    uint256 private threshold;
    address[] private rewardTokensAddresses;

    event TransferToStaking(uint256 indexed amount, uint256 timestamp);
    event TransferToOwner(uint256 indexed amount, uint256 timestamp);
    event TokensSwapped(address indexed token, uint256 amountIn, uint256 amountOut);

    function initialize(
        NexStaking _nexStagingAddress,
        address[] memory _rewardTokensAddresses,
        address _uniswapRouter,
        address _uniswapV2Router,
        address _weth,
        address _usdc,
        uint256 _threshold
    ) public initializer {
        __Ownable_init(msg.sender);

        nexStaking = NexStaking(_nexStagingAddress);
        uniswapRouter = ISwapRouter(_uniswapRouter);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        weth = IWETH9(_weth);
        usdc = IERC20(_usdc);
        threshold = _threshold * 10 ** 18;

        rewardTokensAddresses = _rewardTokensAddresses;
    }

    function checkAndTransfer() external onlyOwner {
        // Swap all reward tokens to WETH (ETH)
        SwapHelpers.swapTokensForTargetToken(uniswapRouter, rewardTokensAddresses, address(weth), 3000);

        uint256 wethBalance = weth.balanceOf(address(this));
        require(wethBalance >= threshold, "WETH balance is below the threshold");

        // Split the WETH balance
        uint256 wethForStaking = wethBalance / 2;
        uint256 wethForOwner = wethBalance - wethForStaking;

        // Withdraw half of WETH to get ETH and transfer to NexStaking
        weth.withdraw(wethForStaking);
        (bool stakingTransferSuccess,) = address(nexStaking).call{value: wethForStaking}("");
        require(stakingTransferSuccess, "Failed to transfer ETH to NexStaking contract");
        emit TransferToStaking(wethForStaking, block.timestamp);

        // Swap the remaining WETH to USDC and transfer to the owner
        uint256 usdcAmount = SwapHelpers.swapTokens(uniswapRouter, address(weth), address(usdc), wethForOwner);

        usdc.safeTransfer(owner(), usdcAmount);
        emit TransferToOwner(usdcAmount, block.timestamp);
    }

    receive() external payable {}

    fallback() external payable {}
}
