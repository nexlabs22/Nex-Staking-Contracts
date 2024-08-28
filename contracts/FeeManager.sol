// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {NexStaging} from "./NexStaging.sol";
import {SwapHelpers} from "./libraries/SwapHelpers.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract FeeManager is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    NexStaging public nexStaging;
    ISwapRouter public uniswapRouter;
    IWETH9 public weth;

    uint256 private threshold;
    address[] private rewardTokensAddresses;

    event TokensSwapped(address indexed token, uint256 amountIn, uint256 amountOut);
    event TransferToStaging(uint256 amount, uint256 timestamp);
    event TransferToOwner(uint256 amount, uint256 timestamp);

    function initialize(
        NexStaging _nexStagingAddress,
        address[] memory _rewardTokensAddresses,
        address _uniswapRouter,
        address _weth,
        uint256 _threshold
    ) public initializer {
        __Ownable_init(msg.sender);

        nexStaging = NexStaging(_nexStagingAddress);
        uniswapRouter = ISwapRouter(_uniswapRouter);
        weth = IWETH9(_weth);
        threshold = _threshold * 10 ** 18;

        for (uint256 i = 0; i < _rewardTokensAddresses.length; i++) {
            rewardTokensAddresses.push(_rewardTokensAddresses[i]);
        }
    }

    function checkAndTransfer() external {
        SwapHelpers.swapTokensForTargetToken(uniswapRouter, rewardTokensAddresses, address(weth), 3000);

        uint256 wethBalance = weth.balanceOf(address(this));
        require(wethBalance >= threshold, "WETH balance is below the threshold");

        // Withdraw WETH to get ETH
        weth.withdraw(wethBalance);

        // Split the ETH balance
        uint256 ethBalance = address(this).balance;
        uint256 amountForOwner = ethBalance / 2;
        uint256 amountForStaging = ethBalance - amountForOwner;

        // Transfer ETH to the contract owner
        (bool ownerTransferSuccess,) = owner().call{value: amountForOwner}("");
        require(ownerTransferSuccess, "Failed to transfer ETH to the owner");
        emit TransferToOwner(amountForOwner, block.timestamp);

        // Transfer ETH to the NexStaging contract
        (bool stagingTransferSuccess,) = address(nexStaging).call{value: amountForStaging}("");
        require(stagingTransferSuccess, "Failed to transfer ETH to NexStaging contract");
        emit TransferToStaging(amountForStaging, block.timestamp);
    }

    receive() external payable {}

    fallback() external payable {}
}
