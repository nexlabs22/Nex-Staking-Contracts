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
import {INonfungiblePositionManager} from "./uniswap/INonfungiblePositionManager.sol";
import {ProposableOwnableUpgradeable} from "./proposable/ProposableOwnableUpgradeable.sol";

contract FeeManager is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    NexStaking public nexStaking;
    ISwapRouter public routerV3;
    IUniswapV2Router02 public routerV2;
    IUniswapV3Factory public factoryV3;
    IWETH9 public weth;
    IERC20 public usdc;
    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    uint256 /*private*/ public threshold;
    address[] public rewardTokensAddresses;
    address[] public poolTokensAddresses;

    mapping(address => uint8) public tokenSwapVersion;

    event RewardsDistributed(address indexed tokenAddress, uint256 amount, uint256 timestamp);
    event RewardDistributionSkipped(address indexed tokenAddress, string reason);
    event TransferToOwner(uint256 indexed usdcAmount, uint256 timestamp);
    event TokensSwapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    function initialize(
        NexStaking _nexStakingAddress,
        address[] memory _indexTokensAddresses,
        address[] memory _rewardTokensAddresses,
        uint8[] memory _swapVersions,
        address _uniswapRouter,
        address _uniswapV2Router,
        address _uniswapV3Factory,
        address _weth,
        address _usdc,
        uint256 _threshold
    ) public initializer {
        __Ownable_init(msg.sender);

        nexStaking = NexStaking(_nexStakingAddress);
        routerV3 = ISwapRouter(_uniswapRouter);
        routerV2 = IUniswapV2Router02(_uniswapV2Router);
        weth = IWETH9(_weth);
        usdc = IERC20(_usdc);
        threshold = _threshold * 10 ** 18;
        factoryV3 = IUniswapV3Factory(_uniswapV3Factory);

        require(_indexTokensAddresses.length == _swapVersions.length, "Swap versions array length mismatch");

        rewardTokensAddresses = _rewardTokensAddresses;
        // poolTokensAddresses = nexStaking.poolTokensAddresses();
        poolTokensAddresses = _indexTokensAddresses;

        _setSwapVersion(_indexTokensAddresses, _swapVersions);
    }

    /// @dev This function checks and processes rewards distribution based on threshold
    function checkAndTransfer() external {
        // Swap all reward tokens to WETH (ETH)
        _swapRewardTokensToWETH();

        uint256 wethBalance = weth.balanceOf(address(this));
        require(wethBalance >= threshold, "WETH balance is below the threshold");

        // // Split the WETH balance
        uint256 wethForOwner = wethBalance / 2;
        uint256 wethForStaking = wethBalance - wethForOwner;

        // Swap half of WETH to USDC and transfer to the owner
        _swapWETHToUSDCAndTransfer(wethForOwner);

        // Distribute the other half of WETH to the staking pools based on pool weights
        _distributeWETHToPools(wethForStaking);
    }

    function _swapRewardTokensToWETH() public {
        for (uint256 i = 0; i < rewardTokensAddresses.length; i++) {
            uint256 tokenBalance = IERC20(rewardTokensAddresses[i]).balanceOf(address(this));
            if (tokenBalance > 0) {
                uint256 swappedAmount = swapTokens(rewardTokensAddresses[i], address(weth), tokenBalance, address(this));
                // uint256 swappedAmount =
                //     SwapHelpers.swapTokens(routerV3, rewardTokensAddresses[i], address(weth), tokenBalance);
                emit TokensSwapped(rewardTokensAddresses[i], address(weth), tokenBalance, swappedAmount);
            }
        }
    }

    /// @dev This function swaps WETH to USDC and transfers to the contract owner
    function _swapWETHToUSDCAndTransfer(uint256 wethAmount) public {
        uint256 swappedAmount = SwapHelpers.swapTokens(routerV3, address(weth), address(usdc), wethAmount);
        usdc.safeTransfer(owner(), swappedAmount);
        emit TransferToOwner(swappedAmount, block.timestamp);
    }

    function _distributeWETHToPools(uint256 wethForStaking) public {
        uint256[] memory poolWeights = calculateWeightOfPools();

        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address vault = nexStaking.tokenAddressToVaultAddress(poolTokensAddresses[i]); // Getting the vault address

            uint256 wethAmountForPool = (wethForStaking * poolWeights[i]) / 1e18;
            if (wethAmountForPool == 0) {
                emit RewardDistributionSkipped(poolTokensAddresses[i], "Weight is zero");
                continue;
            }

            uint256 tokenAmountForPool = swapTokens(address(weth), poolTokensAddresses[i], wethAmountForPool, vault);
            // uint256 tokenAmountForPool =
            //     swapTokens(address(weth), poolTokensAddresses[i], wethAmountForPool, address(this));
            // IERC20(poolTokensAddresses[i]).approve(vault, tokenAmountForPool);
            // IERC20(poolTokensAddresses[i]).safeTransfer(vault, tokenAmountForPool);

            emit RewardsDistributed(poolTokensAddresses[i], tokenAmountForPool, block.timestamp);
        }
    }

    function calculateWeightOfPools() public /*view*/ returns (uint256[] memory) {
        uint256 totalValueAcrossAllPools = getPortfolioBalance();
        uint256[] memory weights = new uint256[](poolTokensAddresses.length);

        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address vault = nexStaking.tokenAddressToVaultAddress(poolTokensAddresses[i]);
            uint256 balance = IERC20(poolTokensAddresses[i]).balanceOf(vault);
            uint256 poolValue =
                getAmountOut(poolTokensAddresses[i], address(weth), balance, tokenSwapVersion[poolTokensAddresses[i]]);

            if (poolValue == 0) {
                continue;
            }

            weights[i] = (poolValue * 1e18) / totalValueAcrossAllPools;
        }

        return weights;
    }

    function getPortfolioBalance() public /*view*/ returns (uint256 totalValue) {
        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address tokenAddress = poolTokensAddresses[i];
            address vault = nexStaking.tokenAddressToVaultAddress(tokenAddress);
            if (tokenAddress == address(weth)) {
                totalValue += IERC20(tokenAddress).balanceOf(vault);
            } else {
                uint256 value = getAmountOut(
                    tokenAddress, address(weth), IERC20(tokenAddress).balanceOf(vault), tokenSwapVersion[tokenAddress]
                );

                totalValue += value;
            }
        }
        return totalValue;
    }

    function swapTokens(address tokenIn, address tokenOut, uint256 amountIn, address _recipient)
        public
        returns (uint256 amountOut)
    {
        IERC20(tokenIn).approve(address(routerV3), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 3000,
            recipient: _recipient,
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        amountOut = routerV3.exactInputSingle(params);
    }

    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn, uint8 _swapVersion)
        public
        returns (
            /*view*/
            uint256 finalAmountOut
        )
    {
        if (amountIn > 0) {
            if (_swapVersion == 3) {
                finalAmountOut = estimateAmountOut(tokenIn, tokenOut, uint128(amountIn));
            } else {
                address[] memory path = new address[](2);
                path[0] = tokenIn;
                path[1] = tokenOut;
                uint256[] memory v2amountOut = routerV2.getAmountsOut(amountIn, path);
                finalAmountOut = v2amountOut[1];
            }
        }
        return finalAmountOut;
    }

    /// @dev Estimate amount out for Uniswap V3 swaps based on current pool tick
    function estimateAmountOut(address tokenIn, address tokenOut, uint128 amountIn)
        public
        returns (
            /*view*/
            uint256 amountOut
        )
    {
        address _pool = factoryV3.getPool(tokenIn, tokenOut, 3000);
        if (_pool == address(0)) {
            ensurePoolExists(tokenIn, tokenOut, 3000);
            _pool = factoryV3.getPool(tokenIn, tokenOut, 3000);
        }
        int24 tick = OracleLibrary.getLatestTick(_pool);
        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }

    function _setSwapVersion(address[] memory _indexTokensAddresses, uint8[] memory _swapVersions) internal {
        for (uint256 i = 0; i < _indexTokensAddresses.length; i++) {
            tokenSwapVersion[_indexTokensAddresses[i]] = _swapVersions[i];
        }
    }

    // ----------------------------------------------------------------------------------------------

    function ensurePoolExists(address tokenIn, address tokenOut, uint24 fee) public {
        // Determine token order for pool creation
        address token0 = tokenIn < tokenOut ? tokenIn : tokenOut;
        address token1 = tokenIn > tokenOut ? tokenIn : tokenOut;

        // Set the initial price (e.g., assuming a ratio of 1:1)
        uint160 sqrtPriceX96 = encodePriceSqrt(1000, 1);

        // Create and initialize the pool
        INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
            token0, token1, fee, sqrtPriceX96
        );
    }

    function encodePriceSqrt(uint256 price1, uint256 price0) internal pure returns (uint160) {
        return uint160(sqrt((price1 * (2 ** 192)) / price0));
    }

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x > 3) {
            z = x;
            uint256 y = x / 2 + 1;
            while (y < z) {
                z = y;
                y = (x / y + y) / 2;
            }
        } else if (x != 0) {
            z = 1;
        }
    }

    // ----------------------------------------------------------------------------------------------

    receive() external payable {}

    fallback() external payable {}
}
