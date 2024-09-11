// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {NexStaking} from "../../../contracts/NexStaking.sol";
import {FeeManager} from "../../../contracts/FeeManager.sol";
import {ERC4626Factory} from "../../../contracts/factory/ERC4626Factory.sol";
import {IWETH9} from "../../../contracts/interfaces/IWETH9.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../../../contracts/libraries/CalculationHelpers.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {INonfungiblePositionManager} from "../../../contracts/uniswap/INonfungiblePositionManager.sol";
import {SwapHelpers} from "../../../contracts/libraries/SwapHelpers.sol";

contract NexStakingTest is Test {
    NexStaking public nexStaking;
    FeeManager public feeManager;
    ERC4626Factory public erc4626Factory;
    IWETH9 public weth;
    ISwapRouter public swapRouterV3;

    MockERC20 public indexToken1;
    MockERC20 public indexToken2;
    MockERC20 public rewardToken1;
    MockERC20 public rewardToken2;
    MockERC20 public nexLabsToken;

    address user = address(1);
    address owner = address(10);

    uint256 mainnetFork;

    address uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address unsiwapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address uniswapV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address nonfungiblePositionManagerAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(uniswapV3FactoryAddress);
    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(nonfungiblePositionManagerAddress);

    IERC20[] indexTokens;
    IERC20[] rewardTokens;

    uint256 public initialBalance = 1000e18;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // Fork the Ethereum mainnet
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        deal(address(this), 10000 ether);

        // Initialize swapRouter, WETH, and Uniswap
        swapRouterV3 = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Uniswap V3 Router
        weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH Address
        // uniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        // nonfungiblePositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88); // Position Manager

        // Deploy mock tokens
        deployTokens();

        // Deploy and initialize contracts
        deployAndInitializeContracts();

        // Add liquidity to Uniswap pools
        addLiquidityToAllPools();

        console.log("Setup complete.");
    }

    function testStakeTokens() public {
        console.log("-----------------testStakeTokens-----------------");

        // deal(indexToken1, user, 1000e18);
        // deal(indexToken2, user, 1000e18);

        // Test staking functionality for user1
        vm.startPrank(user);

        // User stakes 500 tokens
        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 sharesAfterStake = nexStaking.getUserShares(user, address(indexTokens[0]));
        assertGt(sharesAfterStake, 0, "Shares should increase after staking");

        vm.stopPrank();

        console.log("-----------------testStakeTokens-----------------");
    }

    function testUnstakeAllTokensWithSameTokenReward() public {
        vm.startPrank(user);

        // User stakes 500 tokens
        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceAfterStake = indexTokens[0].balanceOf(user);

        // Approve NexStaking for redeeming shares from the vault
        address vault = nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), 500e18);

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(500e18, 3);

        // Unstake all tokens and receive rewards
        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee);

        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        assertGt(userBalanceAfterUnStake, userBalanceAfterStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        assertEq(remainingShares, 0, "All shares should be redeemed");

        vm.stopPrank();
    }

    function testUnstakeSomeTokensWithSameTokenReward() public {
        console.log("-----------------testUnstakeAllTokens-----------------");

        vm.startPrank(user);

        // User stakes 500 tokens
        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceAfterStake = indexTokens[0].balanceOf(user);

        // Approve NexStaking for redeeming shares from the vault
        address vault = nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), 500e18);

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(250e18, 3);

        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee);

        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        assertGt(userBalanceAfterUnStake, userBalanceAfterStake);

        uint256 expectedRemainingShares = ERC4626(vault).balanceOf(user);
        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        assertEq(remainingShares, expectedRemainingShares, "All shares should be redeemed");

        vm.stopPrank();

        console.log("-----------------testUnstakeAllTokens-----------------");
    }

    function testUnstakeAllTokensWithDifferentRewardToken() public {
        vm.startPrank(user);

        // User stakes 500 tokens
        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceBeforeUnStake = indexTokens[0].balanceOf(user);

        // Approve NexStaking for redeeming shares from the vault
        address vault = nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), 500e18);

        deal(address(indexTokens[0]), vault, 111e18);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user));

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(500e18, 3);

        uint256 userRewardTokenBalanceBeforeUnstake = rewardTokens[1].balanceOf(user);
        uint256 stakingContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("Staking contract balance before unstake: ", stakingContractBalance);

        // Unstake all tokens and receive rewards
        nexStaking.unstake(address(indexTokens[0]), address(rewardTokens[1]), amountAfterFee);

        uint256 userRewardTokenBalanceAfterUnstake = rewardTokens[1].balanceOf(user);
        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        assertGt(userRewardTokenBalanceAfterUnstake, userRewardTokenBalanceBeforeUnstake);
        assertGt(userBalanceAfterUnStake, userBalanceBeforeUnStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        assertEq(remainingShares, 0, "All shares should be redeemed");

        vm.stopPrank();
    }

    // function testUnstakeAllTokensWithDifferentRewardToken() public {
    //     vm.startPrank(user);

    //     // User stakes 500 tokens
    //     indexTokens[0].approve(address(nexStaking), 500e18);
    //     nexStaking.stake(address(indexTokens[0]), 500e18);

    //     uint256 userBalanceAfterStake = indexTokens[0].balanceOf(user);

    //     // Approve NexStaking for redeeming shares from the vault
    //     address vault = nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]));
    //     ERC4626(vault).approve(address(nexStaking), 500e18);

    //     (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(500e18, 3);

    //     uint256 userRewardTokenBalanceBeforeUnstake = rewardTokens[0].balanceOf(user);

    //     // Unstake all tokens and receive rewards
    //     nexStaking.unstake(address(indexTokens[0]), address(rewardTokens[1]), amountAfterFee);

    //     uint256 userRewardTokenBalanceAfterUnstake = rewardTokens[0].balanceOf(user);

    //     uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

    //     assertGt(userRewardTokenBalanceAfterUnstake, userRewardTokenBalanceBeforeUnstake);

    //     assertGt(userBalanceAfterUnStake, userBalanceAfterStake);

    //     uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
    //     assertEq(remainingShares, 0, "All shares should be redeemed");

    //     vm.stopPrank();
    // }

    function testSwapIndexToReward() public {
        console.log("-----------------testSwapIndexToReward-----------------");

        vm.startPrank(user);

        // Approve the router to spend the user's index tokens
        indexTokens[0].approve(address(swapRouterV3), 500e18);

        // Define the swap path (indexToken1 -> WETH -> rewardToken1)
        address[] memory path = new address[](3);
        path[0] = address(indexTokens[0]); // Swap from indexToken1
        path[1] = address(weth); // Intermediary WETH
        path[2] = address(rewardTokens[1]); // Swap to rewardToken1

        // Check initial balances
        uint256 initialRewardBalance = rewardTokens[1].balanceOf(user);
        uint256 initialIndexBalance = indexTokens[0].balanceOf(user);

        // Perform the swap
        uint256 amountIn = 500e18; // Amount to swap
        uint256 amountOut = SwapHelpers.swapIndexToReward(swapRouterV3, path, amountIn, user);

        // Verify that the rewardToken1 balance has increased and indexToken1 balance has decreased
        uint256 finalRewardBalance = rewardTokens[1].balanceOf(user);
        uint256 finalIndexBalance = indexTokens[0].balanceOf(user);

        assertGt(finalRewardBalance, initialRewardBalance, "Reward token balance should increase after the swap");
        assertLt(finalIndexBalance, initialIndexBalance, "Index token balance should decrease after the swap");

        console.log("Amount Out: ", amountOut);
        console.log("Reward Token Balance After Swap: ", finalRewardBalance);

        vm.stopPrank();

        console.log("-----------------testSwapIndexToReward-----------------");
    }

    function testCalculateAmountAfterFee() public {
        (uint256 fee, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(1e18, 3);
        uint256 expectedFee = (1e18 * 3) / 10000;
        uint256 expectedAmount = 1e18 - expectedFee;
        assertEq(fee, expectedFee, "Fee should be 3%");
        assertEq(amountAfterFee, expectedAmount, "Amount after fee should be 95%");
    }

    function testInitializeStaking() public {
        // Check the NexLabs Token
        assertEq(address(nexStaking.nexLabsToken()), address(nexLabsToken), "NexLabs Token is incorrect");

        // Check the pool tokens (index tokens)
        assertEq(nexStaking.poolTokensAddresses(0), address(indexTokens[0]), "Index Token 1 is incorrect");
        assertEq(nexStaking.poolTokensAddresses(1), address(indexTokens[1]), "Index Token 2 is incorrect");

        // Check the reward tokens (remember index tokens are included)
        assertEq(
            nexStaking.rewardTokensAddresses(0),
            address(indexTokens[0]),
            "Reward Token 1 is incorrect (should be Index Token 1)"
        );
        assertEq(
            nexStaking.rewardTokensAddresses(1),
            address(rewardTokens[1]),
            "Reward Token 2 is incorrect (specific reward token or index token)"
        );
        assertEq(
            nexStaking.rewardTokensAddresses(2),
            address(indexTokens[1]),
            "Reward Token 3 is incorrect (should be Index Token 2)"
        );
    }

    // function testInitializeStaking() public {
    //     assertEq(address(nexStaking.nexLabsToken()), address(nexLabsToken), "NexLabs Token is incorrect");
    //     assertEq(nexStaking.poolTokensAddresses(0), address(indexToken1), "Index Token 1 is incorrect");
    //     assertEq(nexStaking.poolTokensAddresses(1), address(indexToken2), "Index Token 2 is incorrect");
    //     assertEq(nexStaking.rewardTokensAddresses(0), address(rewardToken1), "Reward Token 1 is incorrect");
    //     assertEq(nexStaking.rewardTokensAddresses(1), address(rewardToken2), "Reward Token 2 is incorrect");
    // }

    function deployTokens() internal {
        nexLabsToken = new MockERC20("NexLabs Token", "NEX", 18);
        // usdc = new MockERC20("USD Coin", "USDC", 6);

        nexLabsToken.mint(address(this), 1e24);
        // deal(address(usdc), address(this), 1e24);

        for (uint256 i = 0; i < 3; i++) {
            // Deploy index tokens
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

            rewardTokens.push(indexToken);

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
            // console.log("Reward Token ", i, " deployed at: ", address(rewardToken));
        }
    }

    function deployAndInitializeContracts() internal {
        // Deploy NexStaking contract
        nexStaking = new NexStaking();
        console.log("Deploying NexStaking");

        // Deploy ERC4626 Factory
        erc4626Factory = new ERC4626Factory();
        console.log("ERC4626Factory deployed");

        uint8[] memory swapVersions = new uint8[](indexTokens.length);
        for (uint256 i = 0; i < swapVersions.length; i++) {
            swapVersions[i] = 3;
        }

        // Initialize NexStaking
        nexStaking.initialize(
            address(nexLabsToken), // NexLabs token address
            addressArray(indexTokens), // Supported staking tokens
            addressArray(rewardTokens), // Supported reward tokens
            swapVersions, // Versions of the swap mechanism (e.g., Uniswap V3)
            address(erc4626Factory), // ERC4626 Factory address
            uniswapV3Router, // Uniswap V3 Router
            address(weth), // WETH address
            3 // Fee percentage
        );

        console.log("Nex Staking deployed at: ", address(nexStaking));

        // Initialize FeeManager
        feeManager = new FeeManager();
        feeManager.initialize(
            nexStaking,
            addressArray(indexTokens),
            addressArray(rewardTokens),
            swapVersions,
            uniswapV3Router,
            unsiwapV2Router,
            address(uniswapV3Factory),
            address(weth),
            address(rewardToken1),
            1 // Threshold
        );

        console.log("FeeManager initialized.");

        // for (uint256 i = 0; i < 3; i++) {
        //     address vault = nexStaking.tokenAddressToVaultAddress(address(indexToken));
        //     indexToken.mint(vault, 10e18);
        // }
    }

    function addLiquidityToAllPools() internal {
        for (uint256 i = 0; i < indexTokens.length; i++) {
            addLiquidity(indexTokens[i]);
        }

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            addLiquidity(rewardTokens[i]);
        }

        // addLiquidity(IERC20(usdc));

        // console.log(msg.sender);
        // console.log(address(this));
    }

    function addLiquidity(IERC20 indexToken) internal {
        // Wrap ETH into WETH
        wrapEthToWeth();

        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 indexTokenBalance = indexToken.balanceOf(address(this));
        // console.log("WETH balance before liquidity: ", wethBalance);
        // console.log("IndexToken balance before liquidity: ", indexTokenBalance);

        require(wethBalance >= 5e18, "Not enough WETH for liquidity");
        require(indexTokenBalance >= 1000e18, "Not enough index tokens for liquidity");

        // console.log("Adding liquidity...");
        address token0 = address(weth) < address(indexToken) ? address(weth) : address(indexToken);
        address token1 = address(weth) > address(indexToken) ? address(weth) : address(indexToken);

        // console.log("Token0: ", token0);
        // console.log("Token1: ", token1);

        // Encode initial price: Assuming 1 WETH = 1000 index tokens
        uint160 initialPrice = encodePriceSqrt(1000, 1);
        console.log("Initial price sqrt: ", uint256(initialPrice));

        // address pool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, 3000);
        address pool = uniswapV3Factory.getPool(token0, token1, 3000);

        if (pool == address(0)) {
            console.log("Pool does not exist, creating and initializing pool");

            INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
                token0, token1, 3000, initialPrice
            );
            // pool = uniswapV3Factory.getPool(token0, token1, 3000);
        } else {
            console.log("Pool already exists: ", pool);
        }

        // IERC20(token0).approve(address(nonfungiblePositionManager), type(uint256).max);
        // IERC20(token1).approve(address(nonfungiblePositionManager), type(uint256).max);
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
        // console.log("Liquidity added for Index Token ", address(indexToken));
        // console.log("Liquidity amount: ", liquidity);
    }

    function wrapEthToWeth() public {
        IWETH9 wethContract = IWETH9(address(weth));
        wethContract.deposit{value: 10 ether}();
    }

    // function wrapEthToWeth() internal {
    //     weth.deposit{value: 10 ether}();
    // }

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

    // function testUnstakeTokensWithReward() public {
    //     console.log("-----------------testUnstakeTokensWithReward-----------------");

    //     // Test unstaking functionality for user1
    //     vm.startPrank(user);

    //     // User stakes 500 tokens first
    //     indexToken1.approve(address(nexStaking), 500e18);
    //     nexStaking.stake(address(indexToken1), 500e18);

    //     // Distribute some rewards
    //     deal(address(indexToken1), address(nexStaking.tokenAddressToVaultAddress(address(indexToken1))), 500e18);

    //     // Unstake the tokens and receive rewards
    //     nexStaking.unstake(address(indexToken1), address(rewardToken1), 250e18);

    //     uint256 remainingShares = nexStaking.getUserShares(user, address(indexToken1));
    //     assertGt(remainingShares, 0, "Shares should decrease after partial unstake");

    //     vm.stopPrank();

    //     console.log("-----------------testUnstakeTokensWithReward-----------------");
    // }

    // function testUnstakeAllTokens() public {
    //     console.log("-----------------testUnstakeAllTokens-----------------");

    //     // Test unstaking all tokens for user1
    //     vm.startPrank(user);

    //     // User stakes 500 tokens
    //     indexToken1.approve(address(nexStaking), 500e18);
    //     nexStaking.stake(address(indexToken1), 500e18);

    //     (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(500e18, 3);

    //     // Unstake all tokens and ensure all shares are redeemed
    //     nexStaking.unstake(address(indexToken1), address(rewardToken1), amountAfterFee);

    //     uint256 remainingShares = nexStaking.getUserShares(user, address(indexToken1));
    //     assertEq(remainingShares, 0, "All shares should be redeemed");

    //     vm.stopPrank();

    //     console.log("-----------------testUnstakeAllTokens-----------------");
    // }

    // function deployTokens() internal {
    //     // Mock tokens for staking, rewards, and NexLabsToken
    //     nexLabsToken = new MockERC20("NexLabs Token", "NEX", 18);
    //     indexToken1 = new MockERC20("Index Token 1", "IDX1", 18);
    //     indexToken2 = new MockERC20("Index Token 2", "IDX2", 18);
    //     rewardToken1 = new MockERC20("Reward Token 1", "RWD1", 18);
    //     rewardToken2 = new MockERC20("Reward Token 2", "RWD2", 18);

    //     // Mint some initial tokens for tests
    //     nexLabsToken.mint(address(this), 1e24);
    //     indexToken1.mint(address(this), 100000e24);
    //     indexToken2.mint(address(this), 100000e24);
    //     indexToken1.mint(user, 100000e24);
    //     indexToken2.mint(user, 100000e24);
    //     rewardToken1.mint(address(this), 100000e24);
    //     rewardToken2.mint(address(this), 100000e24);

    //     deal(address(indexToken1), user, 1000e18);
    //     deal(address(rewardToken1), user, 1000e18);

    //     indexTokens.push(indexToken1);
    //     indexTokens.push(indexToken2);
    //     rewardTokens.push(rewardToken1);
    //     rewardTokens.push(rewardToken2);
    // }

    // function deployAndInitializeContracts() internal {
    //     // Deploy NexStaking contract
    //     nexStaking = new NexStaking();
    //     console.log("Deploying NexStaking");

    //     // Deploy ERC4626 Factory
    //     erc4626Factory = new ERC4626Factory();
    //     console.log("ERC4626Factory deployed");

    //     uint8[] memory swapVersions = new uint8[](indexTokens.length);
    //     for (uint256 i = 0; i < swapVersions.length; i++) {
    //         swapVersions[i] = 3;
    //     }

    //     // Initialize NexStaking
    //     nexStaking.initialize(
    //         address(nexLabsToken),
    //         addressArray(indexTokens),
    //         addressArray(rewardTokens),
    //         swapVersions,
    //         address(erc4626Factory),
    //         uniswapV3Router,
    //         address(weth),
    //         3
    //     );

    //     console.log("Nex Staking deployed at: ", address(nexStaking));

    //     // Initialize FeeManager
    //     feeManager = new FeeManager();
    //     feeManager.initialize(
    //         nexStaking,
    //         addressArray(indexTokens),
    //         addressArray(rewardTokens),
    //         swapVersions,
    //         uniswapV3Router,
    //         unsiwapV2Router,
    //         address(uniswapV3Factory),
    //         address(weth),
    //         address(rewardToken1),
    //         1
    //     );

    //     console.log("FeeManager initialized.");
    // }
}
