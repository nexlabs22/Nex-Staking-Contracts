// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../../contracts/FeeManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../../../contracts/uniswap/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../mocks/MockERC20.sol";
import "../../../contracts/NexStaking.sol";
import "../../../contracts/uniswap/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "../../../contracts/factory/ERC4626Factory.sol";
import "../../../contracts/interfaces/IWETH9.sol";

contract FeeManagerSwapForkTest is Test {
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
    // address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address unsiwapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address uniswapV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    // address rewardToken1Address = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // Use WBTC as reward token
    // address rewardToken2Address = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // Use LINK as reward token

    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(uniswapV3FactoryAddress);

    address user = address(1);
    address owner = address(10);

    IERC20[] indexTokens;
    IERC20[] rewardTokens;
    // MockERC20[] indexTokens;
    // MockERC20[] rewardTokens;

    uint256 public initialBalance = 1000e18;
    // uint256 public initialContractBalance = initialBalance

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // Fork the mainnet
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        deal(address(this), 10000 ether);

        swapRouterV3 = ISwapRouter(uniswapV3Router);
        weth = IWETH9(wethAddress);
        // usdc = IERC20(usdcAddress);
        // rewardToken1 = IERC20(rewardToken1Address);
        // rewardToken2 = IERC20(rewardToken2Address);
        deployTokens();

        deployAndInitializeContracts();

        addLiquidityToAllPools();

        console.log("Setup complete.");
    }

    function deployTokens() internal {
        // Deploy the NexLabs token (MockERC20)
        nexLabsToken = new MockERC20("NexLabs Token", "NEX", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        nexLabsToken.mint(address(this), 1e24);
        deal(address(usdc), address(this), 1e24);

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
        nexStaking = new NexStaking();
        console.log("Deploying NexStaking");

        // Deploy ERC4626Factory (if required)
        erc4626Factory = new ERC4626Factory();
        console.log("ERC4626Factory deployed");

        nexLabsToken = new MockERC20("NexLabs Token", "NEX", 18);

        uint8[] memory swapVersions = new uint8[](indexTokens.length);
        for (uint256 i = 0; i < swapVersions.length; i++) {
            swapVersions[i] = 3;
        }

        // uint8[] memory swapVersions = new uint8[](1);
        // swapVersions[0] = 3;

        // vm.startBroadcast(owner);

        nexStaking.initialize(
            address(nexLabsToken),
            addressArray(indexTokens),
            // addressArray(indexTokens),
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
            // addressArray(indexTokens),
            addressArray(rewardTokens),
            swapVersions,
            uniswapV3Router,
            unsiwapV2Router,
            address(uniswapV3Factory),
            address(weth),
            address(usdc),
            1
        );

        // vm.stopBroadcast();

        console.log("FeeManager initialized at address: ", address(feeManager));
        console.log("Owner address", owner);
    }

    function testSwapRewardTokensToWETH() public {
        // Simulate FeeManager receiving reward tokens
        console.log("-----------------testSwapRewardTokensToWETH-----------------");
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            deal(address(rewardTokens[i]), address(feeManager), 1000e18); // Deal 1000 reward tokens to FeeManager
        }

        // Capture the initial WETH balance
        uint256 initialWETHBalance = weth.balanceOf(address(feeManager));

        // Execute the function to swap reward tokens to WETH
        feeManager._swapRewardTokensToWETH();

        // Capture the new WETH balance
        uint256 newWETHBalance = weth.balanceOf(address(feeManager));

        // Ensure that WETH balance increased after swapping reward tokens
        assertGt(newWETHBalance, initialWETHBalance, "WETH balance should increase after swapping reward tokens");

        // Log output for debugging
        console.log("Initial WETH balance: ", initialWETHBalance);
        console.log("New WETH balance after swap: ", newWETHBalance);
        console.log("-----------------testSwapRewardTokensToWETH-----------------");
    }

    function testSwapWETHToUSDCAndTransfer() public {
        deal(wethAddress, address(feeManager), 10e18);

        uint256 initialUSDCBalance = usdc.balanceOf(address(this));
        console.log("USDC balance before swap", initialUSDCBalance);

        feeManager._swapWETHToUSDCAndTransfer(5e18);
        // feeManager.checkAndTransfer();

        uint256 usdcBalanceAfter = usdc.balanceOf(address(this));
        assertGt(usdcBalanceAfter, initialUSDCBalance, "USDC balance did not increase after swap");

        console.log("USDC balance after swap: ", usdcBalanceAfter);
    }

    function testDistributeWETHToPools() public {
        console.log("-----------------testDistributeWETHToPools-----------------");

        // Allocate WETH to FeeManager
        deal(address(weth), address(feeManager), 10e18); // Allocate 10 WETH to FeeManager

        // Mock staking and vault setup
        deal(address(indexTokens[0]), address(nexStaking), 1000e18);
        deal(address(indexTokens[1]), address(nexStaking), 1000e18);

        address vault1 = nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]));
        address vault2 = nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]));
        deal(address(indexTokens[0]), vault1, 1000e18);
        deal(address(indexTokens[1]), vault2, 1000e18);

        for (uint256 i = 0; i < indexTokens.length; i++) {
            ensureUniswapV3PoolExists(address(indexTokens[i]), address(weth), 3000);
        }

        // Approve tokens for staking pools
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

        // Verify that the WETH was distributed
        // assertGt(finalVault1Balance, initialVault1Balance, "Vault 1 WETH balance should increase");
        // assertGt(finalVault2Balance, initialVault2Balance, "Vault 2 WETH balance should increase");

        // // Log output for debugging
        // console.log("Initial Vault 1 WETH balance: ", initialVault1Balance);
        // console.log("Final Vault 1 WETH balance: ", finalVault1Balance);
        // console.log("Initial Vault 2 WETH balance: ", initialVault2Balance);
        // console.log("Final Vault 2 WETH balance: ", finalVault2Balance);
        console.log("-----------------testDistributeWETHToPools-----------------");
    }

    function testGetPortfolioBalance() public {
        console.log("-----------------testGetPortfolioBalance-----------------");

        // Add liquidity to all pools (WETH/Index tokens)
        // addLiquidityToAllPools();

        // Deal some mock index tokens to the vaults
        deal(address(indexTokens[0]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]))), 500e18);
        deal(address(indexTokens[1]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]))), 300e18);
        deal(address(indexTokens[2]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[2]))), 200e18);

        // Simulate WETH in the vaults
        // deal(address(weth), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]))), 100e18);
        // deal(address(weth), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]))), 50e18);
        // deal(address(weth), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[2]))), 25e18);

        // Get actual portfolio balance from the contract
        uint256 portfolioBalance = feeManager.getPortfolioBalance();

        // Calculate the expected portfolio value based on WETH and index tokens converted to WETH
        // uint256 expectedPortfolioValue = 100e18 + 50e18 + 25e18; // Direct WETH in vaults
        uint256 expectedPortfolioValue; // Direct WETH in vaults

        // For each index token, use getAmountOut to calculate its value in WETH
        uint256 indexToken0ToWeth = feeManager.getAmountOut(address(indexTokens[0]), address(weth), 500e18, 3);
        uint256 indexToken1ToWeth = feeManager.getAmountOut(address(indexTokens[1]), address(weth), 300e18, 3);
        uint256 indexToken2ToWeth = feeManager.getAmountOut(address(indexTokens[2]), address(weth), 200e18, 3);

        // Add the converted values to the expected portfolio value
        expectedPortfolioValue += indexToken0ToWeth;
        expectedPortfolioValue += indexToken1ToWeth;
        expectedPortfolioValue += indexToken2ToWeth;

        // Log the calculated portfolio balance for debugging purposes
        console.log("Total portfolio balance in WETH: ", portfolioBalance);
        console.log("Expected portfolio balance in WETH: ", expectedPortfolioValue);

        // Assert the calculated balance is equal to the expected value
        assertEq(portfolioBalance, expectedPortfolioValue, "Portfolio balance is incorrect");

        console.log("-----------------testGetPortfolioBalance-----------------");
    }

    // function testGetPortfolioBalance() public {
    //     console.log("-----------------testGetPortfolioBalance-----------------");

    //     // Add liquidity to all pools (WETH/Index tokens)
    //     addLiquidityToAllPools();

    //     // Deal some mock index tokens to the vaults
    //     deal(address(indexTokens[0]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]))), 500e18);
    //     deal(address(indexTokens[1]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]))), 300e18);
    //     deal(address(indexTokens[2]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[2]))), 200e18);

    //     // Simulate WETH in the vaults
    //     deal(address(weth), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]))), 100e18);
    //     deal(address(weth), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]))), 50e18);
    //     deal(address(weth), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[2]))), 25e18);

    //     // Call the portfolio balance calculation
    //     uint256 portfolioBalance = feeManager.getPortfolioBalance();

    //     // We need to calculate the expected portfolio value based on WETH in vaults + index tokens value in WETH
    //     // Assuming for this test that the conversion rate is 1:1 for index tokens to WETH
    //     uint256 expectedPortfolioValue = 100e18 + 50e18 + 25e18; // Direct WETH in vaults
    //     // uint256 expectedPortfolioValue; // Direct WETH in vaults
    //     expectedPortfolioValue += 500e18 + 300e18 + 200e18; // Index tokens converted to WETH (assuming 1:1 rate)

    //     // Log the calculated portfolio balance for debugging purposes
    //     console.log("Total portfolio balance in WETH: ", portfolioBalance);

    //     // Assert the calculated balance is equal to the expected value
    //     assertEq(portfolioBalance, expectedPortfolioValue, "Portfolio balance is incorrect");

    //     console.log("-----------------testGetPortfolioBalance-----------------");
    // }

    // function testCalculateWeightOfPools() public {
    //     console.log("-----------------testCalculateWeightOfPools-----------------");

    //     // Deal some mock tokens and WETH to the vaults to simulate pool holdings
    //     deal(address(indexTokens[0]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]))), 500e18);
    //     deal(address(indexTokens[1]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]))), 300e18);
    //     // deal(address(indexTokens[2]), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[2]))), 200e18);

    //     // Ensure there is also some WETH in the vaults
    //     deal(indexTokens[0], address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]))), 100e18);
    //     deal(indexTokens[1], address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[1]))), 50e18);
    //     // deal(address(weth), address(nexStaking.tokenAddressToVaultAddress(address(indexTokens[2]))), 25e18);

    //     uint256[] memory poolWeights = feeManager.calculateWeightOfPools();

    //     // Print the weights for debugging
    //     for (uint256 i = 0; i < poolWeights.length; i++) {
    //         console.log("Pool ", i, " weight: ", poolWeights[i]);
    //     }

    //     // Expected weights can be calculated based on mock data
    //     assertApproxEq(poolWeights[0], expectedWeightForPool1, "Weight for pool 1 is incorrect");
    //     assertApproxEq(poolWeights[1], expectedWeightForPool2, "Weight for pool 2 is incorrect");
    //     assertApproxEq(poolWeights[2], expectedWeightForPool3, "Weight for pool 3 is incorrect");

    //     console.log("-----------------testCalculateWeightOfPools-----------------");
    // }

    function testSwapTokens() public {
        vm.selectFork(mainnetFork);

        uint256 initialUsdcBalance = usdc.balanceOf(address(this));

        // deal(address(weth), address(this), 100e18);
        weth.deposit{value: 10e18}();
        weth.transfer(address(feeManager), 10e18);

        // Approve FeeManager to swap WETH
        weth.approve(address(feeManager), 10e18);

        uint256 amountOut = feeManager.swapTokens(address(weth), address(usdc), 10e18, address(this));

        uint256 UsdcBalanceAfterSwap = usdc.balanceOf(address(this));

        assertEq(initialUsdcBalance + amountOut, UsdcBalanceAfterSwap);

        // console.log("Output amount ", swapRouterV3.exactInputSingle(params));
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

    function ensureUniswapV3PoolExists(address tokenA, address tokenB, uint24 fee) internal {
        address pool = IUniswapV3Factory(uniswapV3Factory).getPool(tokenA, tokenB, fee);

        if (pool == address(0)) {
            console.log("Creating and initializing Uniswap V3 pool for tokens:", tokenA, tokenB);

            // Determine token order for pool creation
            address token0 = tokenA < tokenB ? tokenA : tokenB;
            address token1 = tokenA > tokenB ? tokenA : tokenB;

            // Set the initial price (assuming 1:1 ratio for simplicity, adjust as needed)
            uint160 initialPrice = encodePriceSqrt(1, 1);

            // Create and initialize the pool
            INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
                token0, token1, fee, initialPrice
            );
        } else {
            console.log("Uniswap V3 pool already exists for tokens:", tokenA, tokenB);
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
