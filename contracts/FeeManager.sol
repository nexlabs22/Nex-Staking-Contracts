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

contract FeeManager is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    NexStaking public nexStaking;
    ISwapRouter public routerV3;
    IUniswapV2Router02 public routerV2;
    IUniswapV3Factory public factoryV3;
    IWETH9 public weth;
    IERC20 public usdc;
    INonfungiblePositionManager public nonfungiblePositionManager;

    uint256 /*private*/ public threshold;
    address[] public rewardTokensAddresses;
    address[] public poolTokensAddresses;

    mapping(address => bool) public supportedToken;
    mapping(address => uint8) public tokenSwapVersion;

    event RewardsDistributed(address indexed tokenAddress, uint256 amount, uint256 timestamp);
    event RewardDistributionSkipped(address indexed tokenAddress, string reason);
    event TransferToOwner(uint256 indexed usdcAmount, uint256 timestamp);
    event TokensSwapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event RewardTokensUpdated(address[] newRewardTokens);
    event PoolTokensUpdated(address[] newPoolTokens);

    function initialize(
        NexStaking _nexStakingAddress,
        address[] memory _indexTokensAddresses,
        address[] memory _rewardTokensAddresses,
        uint8[] memory _swapVersions,
        address _uniswapRouter,
        address _uniswapV2Router,
        address _uniswapV3Factory,
        address _nonfungiblePositionManager,
        address _weth,
        address _usdc,
        uint256 _threshold
    ) public initializer {
        __Ownable_init(msg.sender);

        nexStaking = NexStaking(_nexStakingAddress);
        routerV3 = ISwapRouter(_uniswapRouter);
        routerV2 = IUniswapV2Router02(_uniswapV2Router);
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        weth = IWETH9(_weth);
        usdc = IERC20(_usdc);
        threshold = _threshold;
        factoryV3 = IUniswapV3Factory(_uniswapV3Factory);

        require(_indexTokensAddresses.length == _swapVersions.length, "Swap versions array length mismatch");

        rewardTokensAddresses = _rewardTokensAddresses;
        poolTokensAddresses = _indexTokensAddresses;

        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            supportedToken[poolTokensAddresses[i]] = true;
        }

        _setSwapVersion(_indexTokensAddresses, _swapVersions);
    }

    function checkAndTransfer() external {
        uint256 balance = address(this).balance;
        weth.deposit{value: balance}();

        uint256 totalValueOfPoolsInWETH = getTotalValueOfAssetsInWeTH();
        require(totalValueOfPoolsInWETH >= threshold, "WETH balance is below the threshold");

        _swapRewardTokensToWETH();

        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 wethForOwner = wethBalance / 2;
        uint256 wethForStaking = wethBalance - wethForOwner;

        _swapWETHToUSDCAndTransfer(wethForOwner);

        _distributeWETHToPools(wethForStaking);
    }

    function _swapRewardTokensToWETH() public /*internal*/ {
        for (uint256 i = 0; i < rewardTokensAddresses.length; i++) {
            uint256 tokenBalance = IERC20(rewardTokensAddresses[i]).balanceOf(address(this));
            if (tokenBalance > 0) {
                uint256 swappedAmount = swapTokens(rewardTokensAddresses[i], address(weth), tokenBalance, address(this));

                emit TokensSwapped(rewardTokensAddresses[i], address(weth), tokenBalance, swappedAmount);
            }
        }
    }

    function _swapWETHToUSDCAndTransfer(uint256 wethAmount) public /*internal*/ {
        uint256 swappedAmount = SwapHelpers.swapTokens(routerV3, address(weth), address(usdc), wethAmount);
        usdc.safeTransfer(owner(), swappedAmount);
        emit TransferToOwner(swappedAmount, block.timestamp);
    }

    function _distributeWETHToPools(uint256 wethForStaking) public /*internal*/ {
        uint256[] memory poolWeights = calculateWeightOfPools();

        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address vault = nexStaking.tokenAddressToVaultAddress(poolTokensAddresses[i]);

            uint256 wethAmountForPool = (wethForStaking * poolWeights[i]) / 1e18;
            if (wethAmountForPool == 0) {
                emit RewardDistributionSkipped(poolTokensAddresses[i], "Weight is zero");
                continue;
            }

            uint256 tokenAmountForPool = swapTokens(address(weth), poolTokensAddresses[i], wethAmountForPool, vault);

            emit RewardsDistributed(poolTokensAddresses[i], tokenAmountForPool, block.timestamp);
        }
    }

    function calculateWeightOfPools() public view returns (uint256[] memory) {
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

    function getPortfolioBalance() public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address tokenAddress = poolTokensAddresses[i];
            address vault = nexStaking.tokenAddressToVaultAddress(tokenAddress);
            uint256 balance = IERC20(tokenAddress).balanceOf(vault);

            uint256 value = getAmountOut(tokenAddress, address(weth), balance, tokenSwapVersion[tokenAddress]);
            totalValue += value;
        }

        return totalValue;
    }

    function getTotalValueOfAssetsInWeTH() public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < rewardTokensAddresses.length; i++) {
            address tokenAddress = rewardTokensAddresses[i];
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));

            uint256 value = getAmountOut(tokenAddress, address(weth), balance, 3);
            totalValue += value;
        }
        uint256 ethBalance = address(this).balance;
        uint256 wethBalance = weth.balanceOf(address(this));
        totalValue += ethBalance;
        totalValue += wethBalance;

        return totalValue;
    }

    function predictAPY(address tokenAddress, uint256 etherAmount) external view returns (uint256 apy) {
        require(supportedToken[tokenAddress], "Unsupported token.");

        address pool = factoryV3.getPool(tokenAddress, address(weth), 3000);
        require(pool != address(0), "Pool does not exist.");

        address vault = nexStaking.tokenAddressToVaultAddress(tokenAddress);

        uint256 totalTokenInPool = IERC20(tokenAddress).balanceOf(vault);

        uint256 totalValueInEther = getAmountOut(tokenAddress, address(weth), totalTokenInPool, 3);

        if (totalValueInEther > 0) {
            apy = (etherAmount * 100) / totalValueInEther;
        } else {
            apy = 0;
        }

        return apy;
    }

    function setNexStaking(NexStaking _nexStakingAddress) external onlyOwner {
        nexStaking = _nexStakingAddress;
    }

    function setRouterV3(ISwapRouter _routerV3) external onlyOwner {
        routerV3 = _routerV3;
    }

    function setRouterV2(IUniswapV2Router02 _routerV2) external onlyOwner {
        routerV2 = _routerV2;
    }

    function setFactoryV3(IUniswapV3Factory _factoryV3) external onlyOwner {
        factoryV3 = _factoryV3;
    }

    function setUsdc(IERC20 _usdc) external onlyOwner {
        usdc = _usdc;
    }

    function setNonfungiblePositionManager(INonfungiblePositionManager _nonfungiblePositionManager)
        external
        onlyOwner
    {
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    function setThreshold(uint256 _threshold) external onlyOwner {
        threshold = _threshold;
    }

    function setRewardTokensAddresses(address[] memory _newRewardTokensAddresses) external onlyOwner {
        require(_newRewardTokensAddresses.length > 0, "New reward tokens array cannot be empty");
        rewardTokensAddresses = _newRewardTokensAddresses;

        emit RewardTokensUpdated(_newRewardTokensAddresses);
    }

    function setPoolTokensAddresses(address[] memory _newPoolTokensAddresses) external onlyOwner {
        require(_newPoolTokensAddresses.length > 0, "New pool tokens array cannot be empty");
        poolTokensAddresses = _newPoolTokensAddresses;
        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            supportedToken[poolTokensAddresses[i]] = true;
        }

        emit PoolTokensUpdated(_newPoolTokensAddresses);
    }

    function getAmountOutForRewardAmount(address tokenIn, address tokenOut, uint256 amountIn)
        public
        view
        returns (uint256)
    {
        uint256 amount1 = getAmountOut(tokenIn, address(weth), amountIn, 3);
        uint256 amount2 = getAmountOut(address(weth), tokenOut, amount1, 3);
        return amount2;
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
        view
        returns (uint256 finalAmountOut)
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

    function estimateAmountOut(address tokenIn, address tokenOut, uint128 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        address _pool = factoryV3.getPool(tokenIn, tokenOut, 3000);
        require(_pool != address(0), "Pool does not exist");

        int24 tick = OracleLibrary.getLatestTick(_pool);

        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);

        return amountOut;
    }

    function _setSwapVersion(address[] memory _indexTokensAddresses, uint8[] memory _swapVersions) internal {
        for (uint256 i = 0; i < _indexTokensAddresses.length; i++) {
            tokenSwapVersion[_indexTokensAddresses[i]] = _swapVersions[i];
        }
    }

    receive() external payable {}

    fallback() external payable {}
}
