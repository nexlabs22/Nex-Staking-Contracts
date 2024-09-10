// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "./../mocks/MockERC20.sol";
import {INonfungiblePositionManager} from "../../../contracts/uniswap/INonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "../../../contracts/uniswap/INonfungiblePositionManager.sol";
import {NexStaking} from "../../../contracts/NexStaking.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {FeeManager} from "../../../contracts/FeeManager.sol";
import {ERC4626Factory} from "../../../contracts/factory/ERC4626Factory.sol";
import {IWETH9} from "../../../contracts/interfaces/IWETH9.sol";

contract FeeManagerTest is Test {
    FeeManager feeManager;
    ISwapRouter swapRouterV3;
    IWETH9 weth;
    IERC20 usdc;
    IERC20 rewardToken1;
    IERC20 rewardToken2;
    MockERC20 nexLabsToken;
    NexStaking nexStaking;
    ERC4626Factory public erc4626Factory;

    uint256 mainnetFork;

    address uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address unsiwapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address uniswapV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address nonfungiblePositionManagerAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(nonfungiblePositionManagerAddress);
    IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(uniswapV3FactoryAddress);

    address user = address(1);
    address owner = address(10);

    IERC20[] indexTokens;
    IERC20[] rewardTokens;

    uint256 public initialBalance = 1000e18;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        deal(address(this), 10000 ether);

        swapRouterV3 = ISwapRouter(uniswapV3Router);
        weth = IWETH9(wethAddress);

        deployTokens();

        deployAndInitializeContracts();

        addLiquidityToAllPools();

        console.log("Setup complete.");
    }

    function testInitializeFeeManager() public {
        console.log("-----------------testInitializeFeeManager-----------------");

        // Verify initialization of FeeManager
        assertEq(address(feeManager.nexStaking()), address(nexStaking), "NexStaking address is incorrect");
        assertEq(address(feeManager.routerV3()), address(swapRouterV3), "Uniswap V3 Router is incorrect");
        assertEq(address(feeManager.routerV2()), unsiwapV2Router, "Uniswap V2 Router is incorrect");
        assertEq(address(feeManager.weth()), wethAddress, "WETH address is incorrect");
        assertEq(address(feeManager.usdc()), address(usdc), "USDC address is incorrect");
        assertEq(feeManager.threshold(), 1 * 1e18, "Threshold is incorrect");

        // Verify the index tokens and reward tokens addresses
        assertEq(feeManager.poolTokensAddresses(0), address(indexTokens[0]), "Index token 1 is incorrect");
        assertEq(feeManager.poolTokensAddresses(1), address(indexTokens[1]), "Index token 2 is incorrect");
        assertEq(feeManager.rewardTokensAddresses(0), address(rewardTokens[0]), "Reward token 1 is incorrect");
        assertEq(feeManager.rewardTokensAddresses(1), address(rewardTokens[1]), "Reward token 2 is incorrect");

        // Verify that the swap versions are correctly initialized
        assertEq(feeManager.tokenSwapVersion(address(indexTokens[0])), 3, "Swap version for token 1 is incorrect");
        assertEq(feeManager.tokenSwapVersion(address(indexTokens[1])), 3, "Swap version for token 2 is incorrect");

        console.log("-----------------testInitializeFeeManager-----------------");
    }

    function deployTokens() internal {
        nexLabsToken = new MockERC20("NexLabs Token", "NEX", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        nexLabsToken.mint(address(this), 1e24);
        deal(address(usdc), address(this), 1e24);

        for (uint256 i = 0; i < 3; i++) {
            MockERC20 indexToken = new MockERC20(
                string(abi.encodePacked("Index Token ", uint8(i + 1))),
                string(abi.encodePacked("IDX", uint8(i + 1))),
                18
            );
            indexTokens.push(indexToken);

            indexToken.mint(address(this), 100000e24);
            indexToken.mint(address(this), 100000e24);
            indexToken.mint(msg.sender, 100000e24);
            indexToken.mint(msg.sender, 100000e24);
            indexToken.mint(user, 100000e24);

            MockERC20 rewardToken = new MockERC20(
                string(abi.encodePacked("Reward Token ", uint8(i + 1))),
                string(abi.encodePacked("RWD", uint8(i + 1))),
                18
            );
            rewardTokens.push(rewardToken);

            rewardToken.mint(address(this), 1e24);
            rewardToken.mint(user, 1e24);
            rewardToken.mint(address(this), 100000e24);
            rewardToken.mint(address(this), 100000e24);
            rewardToken.mint(msg.sender, 100000e24);
            rewardToken.mint(msg.sender, 100000e24);
            rewardToken.mint(user, 100000e24);

            console.log("Index Token ", i, " deployed at: ", address(indexToken));
        }
    }

    function deployAndInitializeContracts() internal {
        nexStaking = new NexStaking();
        console.log("Deploying NexStaking");

        erc4626Factory = new ERC4626Factory();
        console.log("ERC4626Factory deployed");

        nexLabsToken = new MockERC20("NexLabs Token", "NEX", 18);

        uint8[] memory swapVersions = new uint8[](indexTokens.length);
        for (uint256 i = 0; i < swapVersions.length; i++) {
            swapVersions[i] = 3;
        }

        nexStaking.initialize(
            address(nexLabsToken),
            addressArray(indexTokens),
            addressArray(rewardTokens),
            swapVersions,
            address(erc4626Factory),
            uniswapV3Router,
            address(weth),
            3
        );

        console.log("Nex Staking deployed at: ", address(nexStaking));

        feeManager = new FeeManager();
        console.log("Deploying FeeManager");

        feeManager.initialize(
            nexStaking,
            addressArray(indexTokens),
            addressArray(rewardTokens),
            swapVersions,
            uniswapV3Router,
            unsiwapV2Router,
            address(uniswapV3Factory),
            address(weth),
            address(usdc),
            1
        );

        console.log("FeeManager initialized at address: ", address(feeManager));
        console.log("Owner address", owner);
    }

    function testSwapRewardTokensToWETH() public {
        console.log("-----------------testSwapRewardTokensToWETH-----------------");
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            deal(address(rewardTokens[i]), address(feeManager), 1000e18);
        }

        uint256 initialWETHBalance = weth.balanceOf(address(feeManager));

        feeManager._swapRewardTokensToWETH();

        uint256 newWETHBalance = weth.balanceOf(address(feeManager));

        assertGt(newWETHBalance, initialWETHBalance, "WETH balance should increase after swapping reward tokens");

        console.log("Initial WETH balance: ", initialWETHBalance);
        console.log("New WETH balance after swap: ", newWETHBalance);
        console.log("-----------------testSwapRewardTokensToWETH-----------------");
    }

    function testSwapWETHToUSDCAndTransfer() public {
        deal(wethAddress, address(feeManager), 10e18);

        uint256 initialUSDCBalance = usdc.balanceOf(address(this));
        console.log("USDC balance before swap", initialUSDCBalance);

        feeManager._swapWETHToUSDCAndTransfer(5e18);

        uint256 usdcBalanceAfter = usdc.balanceOf(address(this));
        assertGt(usdcBalanceAfter, initialUSDCBalance, "USDC balance did not increase after swap");

        console.log("USDC balance after swap: ", usdcBalanceAfter);
    }

    function testDistributeWETHToPools() public {
        console.log("-----------------testDistributeWETHToPools-----------------");

        deal(address(weth), address(feeManager), 10e18);

        deal(address(indexTokens[0]), address(nexStaking), 1000e18);
        deal(address(indexTokens[1]), address(nexStaking), 1000e18);

        address vault1 = nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]));
        address vault2 = nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]));
        deal(address(indexTokens[0]), vault1, 1000e18);
        deal(address(indexTokens[1]), vault2, 1000e18);

        vm.startPrank(user);
        indexTokens[0].approve(address(nexStaking), 1000e18);
        indexTokens[1].approve(address(nexStaking), 1000e18);
        nexStaking.stake(address(indexTokens[0]), 1e18);
        console.log("Token Staked");
        nexStaking.stake(address(indexTokens[1]), 1e18);
        vm.stopPrank();

        // Call the function to distribute WETH to pools
        uint256 feeManagerBalance = weth.balanceOf(address(feeManager));
        feeManager._distributeWETHToPools(feeManagerBalance);
        console.log("Weth Distributed");

        console.log("-----------------testDistributeWETHToPools-----------------");
    }

    function testGetPortfolioBalance() public {
        console.log("-----------------testGetPortfolioBalance-----------------");

        deal(address(indexTokens[0]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]))), 500e18);
        deal(address(indexTokens[1]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]))), 300e18);
        deal(address(indexTokens[2]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[2]))), 200e18);

        uint256 portfolioBalance = feeManager.getPortfolioBalance();

        uint256 expectedPortfolioValue;

        uint256 indexToken0ToWeth = feeManager.getAmountOut(address(indexTokens[0]), address(weth), 500e18, 3);
        uint256 indexToken1ToWeth = feeManager.getAmountOut(address(indexTokens[1]), address(weth), 300e18, 3);
        uint256 indexToken2ToWeth = feeManager.getAmountOut(address(indexTokens[2]), address(weth), 200e18, 3);

        expectedPortfolioValue += indexToken0ToWeth;
        expectedPortfolioValue += indexToken1ToWeth;
        expectedPortfolioValue += indexToken2ToWeth;

        console.log("Total portfolio balance in WETH: ", portfolioBalance);
        console.log("Expected portfolio balance in WETH: ", expectedPortfolioValue);

        assertEq(portfolioBalance, expectedPortfolioValue, "Portfolio balance is incorrect");

        console.log("-----------------testGetPortfolioBalance-----------------");
    }

    function testCalculateWeightOfPools() public {
        console.log("-----------------testCalculateWeightOfPools-----------------");

        deal(address(indexTokens[0]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]))), 500e18);
        deal(address(indexTokens[1]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]))), 300e18);
        deal(address(indexTokens[2]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[2]))), 200e18);

        uint256[] memory poolWeights = feeManager.calculateWeightOfPools();

        uint256 indexToken0ToWeth = feeManager.getAmountOut(address(indexTokens[0]), address(weth), 500e18, 3);
        uint256 indexToken1ToWeth = feeManager.getAmountOut(address(indexTokens[1]), address(weth), 300e18, 3);
        uint256 indexToken2ToWeth = feeManager.getAmountOut(address(indexTokens[2]), address(weth), 200e18, 3);

        uint256 totalPortfolioValue = 100e18 + 50e18 + 25e18;
        totalPortfolioValue += indexToken0ToWeth + indexToken1ToWeth + indexToken2ToWeth;

        uint256 expectedWeightPool0 = ((100e18 + indexToken0ToWeth) * 1e18) / totalPortfolioValue;
        uint256 expectedWeightPool1 = ((50e18 + indexToken1ToWeth) * 1e18) / totalPortfolioValue;
        uint256 expectedWeightPool2 = ((25e18 + indexToken2ToWeth) * 1e18) / totalPortfolioValue;

        for (uint256 i = 0; i < poolWeights.length; i++) {
            console.log("Pool ", i, " weight: ", poolWeights[i]);
        }

        assertApproxEqAbs(poolWeights[0], expectedWeightPool0, 1e16, "Weight for pool 0 is incorrect");
        assertApproxEqAbs(poolWeights[1], expectedWeightPool1, 1e16, "Weight for pool 1 is incorrect");
        assertApproxEqAbs(poolWeights[2], expectedWeightPool2, 1e16, "Weight for pool 2 is incorrect");

        console.log("-----------------testCalculateWeightOfPools-----------------");
    }

    function testSwapTokens() public {
        vm.selectFork(mainnetFork);

        uint256 initialUsdcBalance = usdc.balanceOf(address(this));

        weth.deposit{value: 10e18}();
        weth.transfer(address(feeManager), 10e18);

        weth.approve(address(feeManager), 10e18);

        uint256 amountOut = feeManager.swapTokens(address(weth), address(usdc), 10e18, address(this));

        uint256 UsdcBalanceAfterSwap = usdc.balanceOf(address(this));

        assertEq(initialUsdcBalance + amountOut, UsdcBalanceAfterSwap);

        console.log("USDC Balance ", usdc.balanceOf(address(this)));
        console.log("Weth balance ", weth.balanceOf(address(this)));
    }

    function addLiquidityToAllPools() internal {
        for (uint256 i = 0; i < indexTokens.length; i++) {
            addLiquidity(indexTokens[i]);
        }

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            addLiquidity(rewardTokens[i]);
        }

        addLiquidity(IERC20(usdc));
    }

    function addLiquidity(IERC20 indexToken) internal {
        wrapEthToWeth();

        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 indexTokenBalance = indexToken.balanceOf(address(this));

        require(wethBalance >= 5e18, "Not enough WETH for liquidity");
        require(indexTokenBalance >= 1000e18, "Not enough index tokens for liquidity");

        address token0 = address(weth) < address(indexToken) ? address(weth) : address(indexToken);
        address token1 = address(weth) > address(indexToken) ? address(weth) : address(indexToken);

        uint160 initialPrice = encodePriceSqrt(1000, 1);
        console.log("Initial price sqrt: ", uint256(initialPrice));

        address pool = uniswapV3Factory.getPool(token0, token1, 3000);

        if (pool == address(0)) {
            console.log("Pool does not exist, creating and initializing pool");

            INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
                token0, token1, 3000, initialPrice
            );
        } else {
            console.log("Pool already exists: ", pool);
        }

        weth.approve(address(nonfungiblePositionManager), type(uint256).max);
        indexToken.approve(address(nonfungiblePositionManager), type(uint256).max);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 3000,
            tickLower: getMinTick(3000),
            tickUpper: getMaxTick(3000),
            amount0Desired: 1000e18,
            amount1Desired: 5e18,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 1200
        });

        INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
        console.log("Liquidity added for Index Token ", address(indexToken));
    }

    function wrapEthToWeth() public {
        IWETH9 wethContract = IWETH9(address(weth));
        wethContract.deposit{value: 10 ether}();
    }

    function getMinTick(int24 tickSpacing) public pure returns (int24) {
        return int24((int256(-887272) / int256(tickSpacing) + 1) * int256(tickSpacing));
    }

    function getMaxTick(int24 tickSpacing) public pure returns (int24) {
        return int24((int256(887272) / int256(tickSpacing)) * int256(tickSpacing));
    }

    function addressArray(IERC20[] memory tokens) internal pure returns (address[] memory) {
        address[] memory addresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            addresses[i] = address(tokens[i]);
        }
        return addresses;
    }

    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) public pure returns (uint160) {
        return uint160(sqrt((reserve1 * (2 ** 192)) / reserve0));
    }

    function sqrt(uint256 y) public pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
