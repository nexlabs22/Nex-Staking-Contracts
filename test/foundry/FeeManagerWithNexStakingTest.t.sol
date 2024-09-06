// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/FeeManager.sol";
import "../../contracts/NexStaking.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/uniswap/INonfungiblePositionManager.sol";
import "./mocks/MockERC20.sol";
import "../../contracts/factory/ERC4626Factory.sol";
import "../../contracts/interfaces/IUniswapV2Router02.sol";
import "../../contracts/interfaces/IUniswapV3Factory2.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract FeeManagerWithNexStakingTest is Test {
    uint256 mainnetFork;

    FeeManager feeManager;
    NexStaking nexStaking;
    MockERC20 nexLabsToken;
    ERC4626Factory public erc4626Factory;

    IERC20 weth;
    IERC20 usdc;

    // Store index and reward tokens
    IERC20[] indexTokens;
    IERC20[] rewardTokens;

    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 24;

    address uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3 Router on mainnet
    address unsiwapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address unsiwapV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address uniswapV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    // address nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88; // Uniswap V3 Position Manager
    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(uniswapV3FactoryAddress);

    address owner;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // Fork the mainnet
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        console.log("Fork created");

        deal(address(this), 100 ether);

        erc4626Factory = new ERC4626Factory();
        console.log("ERC4626Factory deployed");

        // Deploy the NexLabs token, index tokens, and reward tokens
        deployTokens();

        // Use real WETH and USDC tokens on mainnet
        weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH mainnet address
        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC mainnet address
        console.log("WETH and USDC addresses set");

        // Deploy NexStaking with NexLabs token, index tokens, and reward tokens
        nexStaking = new NexStaking();
        console.log("Deploying NexStaking");

        nexStaking.initialize(
            address(nexLabsToken), // NexLabs token
            addressArray(indexTokens), // Array of index tokens
            addressArray(rewardTokens), // Array of reward tokens
            new uint8[](indexTokens.length), // Empty swapVersions array (for simplicity)
            address(erc4626Factory), // ERC4626 factory (not used)
            uniswapV3Router, // Uniswap V3 router
            address(weth), // WETH address
            5 // Fee percentage
        );
        console.log("NexStaking initialized");

        // Deploy FeeManager with NexLabs token, 3 index tokens, and 3 reward tokens
        feeManager = new FeeManager();
        console.log("Deploying FeeManager");

        feeManager.initialize(
            nexStaking, // NexStaking address
            addressArray(indexTokens), // Array of index tokens
            addressArray(rewardTokens), // Array of reward tokens
            uniswapV3Router, // Uniswap V3 router on mainnet
            unsiwapV2Router, // Uniswap V2 router (not used in this test)
            address(weth), // WETH mainnet address
            address(usdc), // USDC mainnet address
            1 // Threshold (in WETH)
        );
        console.log("FeeManager initialized");

        // Add liquidity for each index token on Uniswap V3
        addLiquidityToAllPools();
    }

    function deployTokens() internal {
        // Deploy the NexLabs token (MockERC20)
        nexLabsToken = new MockERC20("NexLabs Token", "NEX");

        // Mint an initial supply of NexLabs tokens to the contract
        nexLabsToken.mint(address(this), 1e24); // 1 million NEX tokens to the contract

        // Deploy index tokens and reward tokens with specific parameters
        for (uint256 i = 0; i < 3; i++) {
            // Deploy index tokens
            MockERC20 indexToken = new MockERC20(
                string(abi.encodePacked("Index Token ", uint8(i + 1))), string(abi.encodePacked("IDX", uint8(i + 1)))
            );
            indexTokens.push(indexToken);

            // Mint initial supply of index tokens to the contract
            indexToken.mint(address(this), 1e24); // 1 million index tokens

            // Deploy reward tokens
            MockERC20 rewardToken = new MockERC20(
                string(abi.encodePacked("Reward Token ", uint8(i + 1))), string(abi.encodePacked("RWD", uint8(i + 1)))
            );
            rewardTokens.push(rewardToken);

            // Mint initial supply of reward tokens to the contract
            rewardToken.mint(address(this), 1e24); // 1 million reward tokens

            // Log the token addresses
            console.log("Index Token ", i, " deployed at: ", address(indexToken));
            console.log("Reward Token ", i, " deployed at: ", address(rewardToken));
        }
    }

    // // Deploy the NexLabs token, 3 index tokens, and 3 reward tokens for testing
    // function deployTokens() internal {
    //     // Deploy the NexLabs token
    //     nexLabsToken = new MockERC20("NexLabs Token", "NEX");

    //     // Mint initial supply of NexLabs tokens to the contract
    //     nexLabsToken.mint(address(this), 1e24); // 1 million NEX tokens to the contract

    //     // Deploy index tokens and reward tokens
    //     for (uint256 i = 0; i < 3; i++) {
    //         // Deploy index tokens
    //         MockERC20 indexToken = new MockERC20(
    //             string(abi.encodePacked("Index Token ", uint8(i + 1))), string(abi.encodePacked("IDX", uint8(i + 1)))
    //         );
    //         indexTokens.push(indexToken);

    //         // Mint initial supply of index tokens to the contract
    //         indexToken.mint(address(this), 1e24); // 1 million tokens

    //         // Deploy reward tokens
    //         MockERC20 rewardToken = new MockERC20(
    //             string(abi.encodePacked("Reward Token ", uint8(i + 1))), string(abi.encodePacked("RWD", uint8(i + 1)))
    //         );
    //         rewardTokens.push(rewardToken);

    //         // Mint initial supply of reward tokens to the contract
    //         rewardToken.mint(address(this), 1e24); // 1 million token
    //         console.log("MockERC20 Index Token deployed at: ", address(indexTokens[i]));
    //     }
    // }

    // Add liquidity for each index token (paired with WETH) on Uniswap V3
    function addLiquidityToAllPools() internal {
        for (uint256 i = 0; i < indexTokens.length; i++) {
            addLiquidity(indexTokens[i]);
        }
    }

    function addLiquidity(IERC20 indexToken) internal {
        // Wrap ETH into WETH
        wrapEthToWeth();

        // Log balances before adding liquidity
        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 indexTokenBalance = indexToken.balanceOf(address(this));
        console.log("WETH balance: ", wethBalance);
        console.log("IndexToken balance: ", indexTokenBalance);

        // Ensure that the contract has sufficient balances
        require(wethBalance >= 5e18, "Not enough WETH");
        require(indexTokenBalance >= 1000e18, "Not enough index tokens");

        // Encode initial price: Assuming 1 WETH = 1000 index tokens
        uint160 initialPrice = encodePriceSqrt(1, 1000);
        console.log("Initial price sqrt: ", uint256(initialPrice));

        // Check if the pool already exists using Uniswap V3 factory
        address pool = IUniswapV3Factory(uniswapV3Factory).getPool(address(indexToken), address(weth), 3000);

        if (pool == address(0)) {
            console.log("Pool does not exist, creating and initializing pool");

            // Create and initialize the pool if it doesn't exist
            INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
                address(indexToken),
                address(weth),
                3000, // Fee tier
                initialPrice // Assuming 1 WETH = 1000 index tokens
            );
        } else {
            console.log("Pool already exists: ", pool);
        }

        weth.approve(address(nonfungiblePositionManager), type(uint256).max);
        indexToken.approve(address(nonfungiblePositionManager), type(uint256).max);

        // Define pool parameters for liquidity
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(indexToken),
            token1: address(weth),
            fee: 3000, // Pool fee of 0.3%
            tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING, // Min tick for liquidity range
            tickUpper: (MAX_TICK / TICK_SPACING) * TICK_SPACING, // Max tick for liquidity range
            amount0Desired: 1000e18, // 1000 index tokens
            amount1Desired: 5e18, // 5 WETH
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 1200 // Deadline of 20 minutes
        });

        // Add liquidity to the Uniswap V3 pool
        (, uint128 liquidity,,) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);

        console.log("Liquidity added for Index Token ", address(indexToken));
        console.log("Liquidity amount: ", liquidity);
    }

    // Wrap ETH to WETH for liquidity provision
    function wrapEthToWeth() public {
        IWETH9 wethContract = IWETH9(address(weth));
        wethContract.deposit{value: 10 ether}(); // Wrap 10 ETH into WETH
    }

    // Test staking in NexStaking
    function testStakeTokensInNexStaking() public {
        // Mint index tokens to test account and approve for staking
        deal(address(indexTokens[0]), address(this), 1000e18); // Deal 1000 index tokens to the test account
        indexTokens[0].approve(address(nexStaking), 1000e18);

        // Stake 500 index tokens
        nexStaking.stake(address(indexTokens[0]), 500e18);
        assertGt(nexStaking.getUserShares(address(this), address(indexTokens[0])), 0, "Staking failed");
    }

    // Test reward swapping from FeeManager
    function testSwapRewardTokensToWETH() public {
        // Simulate FeeManager receiving 1000 reward tokens of each type
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            deal(address(rewardTokens[i]), address(feeManager), 1000e18); // Deal 1000 reward tokens to FeeManager
        }

        // Perform swaps for all reward tokens
        feeManager.checkAndTransfer();

        // Assert that WETH was received by FeeManager after each swap
        uint256 wethBalanceAfter = weth.balanceOf(address(feeManager));
        assertGt(wethBalanceAfter, 0, "WETH balance should increase after swaps");
    }

    // Test unstaking tokens from NexStaking
    function testUnstakeTokensFromNexStaking() public {
        // Mint index tokens and stake them first
        deal(address(indexTokens[0]), address(this), 1000e18);
        indexTokens[0].approve(address(nexStaking), 1000e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        // Now unstake 250 tokens
        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), 250e18);
        assertEq(indexTokens[0].balanceOf(address(this)), 250e18, "Unstaking failed");
    }

    // Helper to convert an array of IERC20 tokens to an array of addresses
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

    // function encodePriceSqrt(uint256 reserve1, uint256 reserve0) public pure returns (uint160) {
    //     uint256 sqrtPriceX96 = sqrt((reserve1 * 2 ** 192) / reserve0);
    //     return uint160(sqrtPriceX96);
    // }

    // function sqrt(uint256 y) public pure returns (uint256 z) {
    //     if (y > 3) {
    //         z = y;
    //         uint256 x = y / 2 + 1;
    //         while (x < z) {
    //             z = x;
    //             x = (y / x + x) / 2;
    //         }
    //     } else if (y != 0) {
    //         z = 1;
    //     }
    // }

    function getMinTick(int24 tickSpacing) public pure returns (int24) {
        return int24((int256(-887272) / int256(tickSpacing) + 1) * int256(tickSpacing));
    }

    function getMaxTick(int24 tickSpacing) public pure returns (int24) {
        return int24((int256(887272) / int256(tickSpacing)) * int256(tickSpacing));
    }
}
