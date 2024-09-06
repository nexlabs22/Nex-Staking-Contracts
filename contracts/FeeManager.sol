// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {NexStaking} from "./NexStaking.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {SwapHelpers} from "./libraries/SwapHelpers.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {OracleLibrary} from "./libraries/OracleLibrary.sol";

contract FeeManager is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    NexStaking public nexStaking;
    ISwapRouter public routerV3;
    IUniswapV2Router02 public routerV2;
    IUniswapV3Factory public factoryV3;
    IWETH9 public weth;
    IERC20 public usdc;

    uint256 private threshold;
    address[] public rewardTokensAddresses;
    address[] public poolTokensAddresses;

    event RewardsDistributed(address indexed tokenAddress, uint256 amount, uint256 timestamp);
    event RewardDistributionSkipped(address indexed tokenAddress, string reason);
    event TransferToOwner(uint256 indexed usdcAmount, uint256 timestamp);
    event TokensSwapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    function initialize(
        NexStaking _nexStagingAddress,
        address[] memory _indexTokensAddresses,
        address[] memory _rewardTokensAddresses,
        address _uniswapRouter,
        address _uniswapV2Router,
        address _weth,
        address _usdc,
        uint256 _threshold
    ) public initializer {
        __Ownable_init(msg.sender);

        nexStaking = NexStaking(_nexStagingAddress);
        routerV3 = ISwapRouter(_uniswapRouter);
        routerV2 = IUniswapV2Router02(_uniswapV2Router);
        weth = IWETH9(_weth);
        usdc = IERC20(_usdc);
        threshold = _threshold * 10 ** 18;

        rewardTokensAddresses = _rewardTokensAddresses;
        // poolTokensAddresses = nexStaking.poolTokensAddresses();
        poolTokensAddresses = _indexTokensAddresses;
    }

    /// @dev This function checks and processes rewards distribution based on threshold
    function checkAndTransfer() external onlyOwner {
        // Swap all reward tokens to WETH (ETH)
        _swapRewardTokensToWETH();

        // uint256 wethBalance = weth.balanceOf(address(this));
        // require(wethBalance >= threshold, "WETH balance is below the threshold");

        // // Split the WETH balance
        // uint256 wethForOwner = wethBalance / 2;
        // uint256 wethForStaking = wethBalance - wethForOwner;

        // Swap half of WETH to USDC and transfer to the owner
        // _swapWETHToUSDCAndTransfer(wethForOwner);

        // Distribute the other half of WETH to the staking pools based on pool weights
        // _distributeWETHToPools(wethForStaking);
    }

    function _swapRewardTokensToWETH() internal {
        for (uint256 i = 0; i < rewardTokensAddresses.length; i++) {
            uint256 tokenBalance = IERC20(rewardTokensAddresses[i]).balanceOf(address(this));
            if (tokenBalance > 0) {
                uint256 swappedAmount = swapTokens(routerV3, rewardTokensAddresses[i], address(weth), tokenBalance);
                // uint256 swappedAmount =
                //     SwapHelpers.swapTokens(routerV3, rewardTokensAddresses[i], address(weth), tokenBalance);
                emit TokensSwapped(rewardTokensAddresses[i], address(weth), tokenBalance, swappedAmount);
            }
        }
    }

    /// @dev This function swaps WETH to USDC and transfers to the contract owner
    function _swapWETHToUSDCAndTransfer(uint256 wethAmount) internal {
        uint256 swappedAmount = SwapHelpers.swapTokens(routerV3, address(weth), address(usdc), wethAmount);
        usdc.safeTransfer(owner(), swappedAmount);
        emit TransferToOwner(swappedAmount, block.timestamp);
    }

    function _distributeWETHToPools(uint256 wethForStaking) internal {
        uint256[] memory poolWeights = calculateWeightOfPools();

        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address vault = nexStaking.tokenAddressToVaultAddress(poolTokensAddresses[i]); // Getting the vault address

            uint256 wethAmountForPool = (wethForStaking * poolWeights[i]) / 1e18;
            if (wethAmountForPool == 0) {
                emit RewardDistributionSkipped(poolTokensAddresses[i], "Weight is zero");
                continue;
            }

            // uint256 tokenAmountForPool =
            //     SwapHelpers.swapTokens(routerV3, address(weth), poolTokensAddresses[i], wethAmountForPool);
            uint256 tokenAmountForPool = swapTokens(routerV3, address(weth), poolTokensAddresses[i], wethAmountForPool);
            IERC20(poolTokensAddresses[i]).approve(vault, tokenAmountForPool);
            IERC20(poolTokensAddresses[i]).safeTransfer(vault, tokenAmountForPool);

            emit RewardsDistributed(poolTokensAddresses[i], tokenAmountForPool, block.timestamp);
        }
    }

    function calculateWeightOfPools() public view returns (uint256[] memory) {
        uint256 totalValueAcrossAllPools = getPortfolioBalance();
        uint256[] memory weights = new uint256[](poolTokensAddresses.length);

        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address vault = nexStaking.tokenAddressToVaultAddress(poolTokensAddresses[i]);
            uint256 balance = IERC20(poolTokensAddresses[i]).balanceOf(vault);
            uint256 poolValue = getAmountOut(
                poolTokensAddresses[i], address(weth), balance, nexStaking.tokenSwapVersion(poolTokensAddresses[i])
            );

            if (poolValue == 0) {
                continue;
            }

            weights[i] = (poolValue * 1e18) / totalValueAcrossAllPools; // Normalize to 18 decimals
        }

        return weights;
    }

    function getPortfolioBalance() public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address tokenAddress = poolTokensAddresses[i];
            address vault = nexStaking.tokenAddressToVaultAddress(tokenAddress);
            if (tokenAddress == address(weth)) {
                totalValue += IERC20(tokenAddress).balanceOf(vault);
            } else {
                uint256 value = getAmountOut(
                    tokenAddress,
                    address(weth),
                    IERC20(tokenAddress).balanceOf(vault),
                    nexStaking.tokenSwapVersion(tokenAddress)
                );
                totalValue += value;
            }
        }
        return totalValue;
    }

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

    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn, uint8 _swapVersion)
        public
        view
        returns (uint256 finalAmountOut)
    {
        if (amountIn > 0) {
            if (_swapVersion == 3) {
                return estimateAmountOut(tokenIn, tokenOut, uint128(amountIn));
            } else {
                address[] memory path = new address[](2);
                path[0] = tokenIn;
                path[1] = tokenOut;
                uint256[] memory v2amountOut = routerV2.getAmountsOut(amountIn, path);
                return v2amountOut[1];
            }
        }
        return 0;
    }

    /// @dev Estimate amount out for Uniswap V3 swaps based on current pool tick
    function estimateAmountOut(address tokenIn, address tokenOut, uint128 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        address _pool = factoryV3.getPool(tokenIn, tokenOut, 3000);
        int24 tick = OracleLibrary.getLatestTick(_pool);
        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }

    receive() external payable {}
}
