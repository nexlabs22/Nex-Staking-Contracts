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

contract FeeManagerSwapForkTest is Test {
    FeeManager feeManager;
    ISwapRouter swapRouterV3;
    IERC20 weth;
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

    uint256 public initialBalance = 1000e18;
    // uint256 public initialContractBalance = initialBalance

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // Fork the mainnet
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        deal(address(this), 10000 ether);

        // Initialize Uniswap V3 Router and Tokens
        swapRouterV3 = ISwapRouter(uniswapV3Router);
        weth = IERC20(wethAddress);
        // usdc = IERC20(usdcAddress);
        // rewardToken1 = IERC20(rewardToken1Address);
        // rewardToken2 = IERC20(rewardToken2Address);
        deployTokens();

        // Deploy the contracts and initialize them
        deployAndInitializeContracts();

        // After contracts are deployed and initialized, mint tokens
        // mintTokensForContracts();

        // Approve tokens for FeeManager to perform swaps
        // approveAllTokens();

        addLiquidityToAllPools();

        console.log("Setup complete.");
    }

    function deployTokens() internal {
        // Deploy the NexLabs token (MockERC20)
        nexLabsToken = new MockERC20("NexLabs Token", "NEX", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mint an initial supply of NexLabs tokens to the contract
        nexLabsToken.mint(address(this), 1e24); // 1 million NEX tokens to the contract
        deal(address(usdc), address(this), 1e24);

        // Deploy index tokens and reward tokens with specific parameters
        for (uint256 i = 0; i < 3; i++) {
            // Deploy index tokens
            MockERC20 indexToken = new MockERC20(
                string(abi.encodePacked("Index Token ", uint8(i + 1))),
                string(abi.encodePacked("IDX", uint8(i + 1))),
                18
            );
            indexTokens.push(indexToken);

            // Mint initial supply of index tokens to the contract
            indexToken.mint(address(this), 100000e24); // 1 million index tokens
            indexToken.mint(user, 100000e24); // 1 million index tokens

            // Deploy reward tokens
            MockERC20 rewardToken = new MockERC20(
                string(abi.encodePacked("Reward Token ", uint8(i + 1))),
                string(abi.encodePacked("RWD", uint8(i + 1))),
                18
            );
            rewardTokens.push(rewardToken);

            // Mint initial supply of reward tokens to the contract
            rewardToken.mint(address(this), 1e24); // 1 million reward tokens
            rewardToken.mint(user, 1e24); // 1 million reward tokens

            // Log the token addresses
            console.log("Index Token ", i, " deployed at: ", address(indexToken));
            console.log("Reward Token ", i, " deployed at: ", address(rewardToken));
        }
    }

    function deployAndInitializeContracts() internal {
        // Deploy NexStaking contract
        nexStaking = new NexStaking();
        console.log("Deploying NexStaking");

        // Deploy ERC4626Factory (if required)
        erc4626Factory = new ERC4626Factory();
        console.log("ERC4626Factory deployed");

        nexLabsToken = new MockERC20("NexLabs Token", "NEX", 18);

        // vm.startBroadcast(owner);

        nexStaking.initialize(
            address(nexLabsToken), // NexLabs token
            addressArray(indexTokens), // Array of index tokens
            addressArray(rewardTokens), // Array of reward tokens
            new uint8[](indexTokens.length), // Empty swapVersions array (for simplicity)
            address(erc4626Factory), // ERC4626 factory (not used)
            uniswapV3Router, // Uniswap V3 router
            address(weth), // WETH address
            3 // Fee percentage
        );

        // Deploy FeeManager contract
        feeManager = new FeeManager(); // Ensure FeeManager is deployed
        console.log("Deploying FeeManager");

        // Initialize FeeManager contract
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

        // vm.stopBroadcast();

        console.log("FeeManager initialized at address: ", address(feeManager));
        console.log("Owner address", owner);
    }

    // function mintTokensForContracts() internal {
    //     // Mint an initial supply of NexLabs tokens to the contract and user
    //     nexLabsToken.mint(address(this), 1e24); // 1 million NEX tokens to the contract
    //     nexLabsToken.mint(user, 1e24); // 1 million NEX tokens to the user

    //     // Deploy index tokens and reward tokens
    //     for (uint256 i = 0; i < 3; i++) {
    //         // Deploy index tokens
    //         MockERC20 indexToken = new MockERC20(
    //             string(abi.encodePacked("Index Token ", uint8(i + 1))), string(abi.encodePacked("IDX", uint8(i + 1)))
    //         );
    //         indexTokens.push(indexToken);

    //         // **Increase the minted amount** to ensure we have enough for liquidity operations
    //         indexToken.mint(address(feeManager), 20000e18); // Mint 2000 tokens to FeeManager
    //         indexToken.mint(user, 20000e18); // Mint 2000 tokens to user
    //         indexToken.mint(address(nexStaking), 20000e18); // Mint 2000 tokens to NexStaking
    //         indexToken.mint(address(this), 2000e18);

    //         // Deploy reward tokens
    //         MockERC20 rewardToken = new MockERC20(
    //             string(abi.encodePacked("Reward Token ", uint8(i + 1))), string(abi.encodePacked("RWD", uint8(i + 1)))
    //         );
    //         rewardTokens.push(rewardToken);

    //         rewardToken.mint(address(feeManager), 200e18); // Mint 200 reward tokens to FeeManager

    //         // Log the token addresses
    //         console.log("Index Token ", i, " deployed at: ", address(indexToken));
    //         console.log("Reward Token ", i, " deployed at: ", address(rewardToken));
    //     }

    //     deal(rewardToken1Address, address(feeManager), 10e18); // 1 WBTC
    //     deal(rewardToken2Address, address(feeManager), 500e18); // 100 LINK
    // }

    // function approveAllTokens() internal {
    //     for (uint256 i = 0; i < indexTokens.length; i++) {
    //         indexTokens[i].approve(address(nexStaking), 20000e18);
    //         indexTokens[i].approve(address(feeManager), 20000e18);
    //     }
    //     for (uint256 i = 0; i < rewardTokens.length; i++) {
    //         rewardTokens[i].approve(address(feeManager), 1000e18);
    //     }
    //     weth.approve(address(feeManager), 10000e18);
    //     usdc.approve(address(feeManager), 10000e18);
    // }

    function testSwapRewardTokensToWETH() public {
        // deal()

        // Log initial balances
        uint256 initialWETHBalance = weth.balanceOf(address(feeManager));
        // console.log("Initial WETH balance of FeeManager: ", initialWETHBalance);

        uint256 initialRewardToken1Balance = rewardToken1.balanceOf(address(feeManager));
        uint256 initialRewardToken2Balance = rewardToken2.balanceOf(address(feeManager));
        console.log("Initial Reward Token 1 balance: ", initialRewardToken1Balance);
        console.log("Initial Reward Token 2 balance: ", initialRewardToken2Balance);

        // Ensure reward tokens are available for swap
        require(initialRewardToken1Balance > 0, "Reward Token 1 balance is zero");
        require(initialRewardToken2Balance > 0, "Reward Token 2 balance is zero");

        // Execute swap from reward tokens to WETH
        feeManager.checkAndTransfer();

        // Verify that WETH balance increased after the swap
        uint256 wethBalanceAfter = weth.balanceOf(address(feeManager));
        assertGt(wethBalanceAfter, initialWETHBalance, "WETH balance did not increase after swap");

        // Log the output for verification
        console.log("WETH balance after swap: ", wethBalanceAfter);
    }

    function testSwapWETHToUSDCAndTransfer() public {
        // Simulate WETH allocation to FeeManager
        deal(wethAddress, address(feeManager), 10e18); // Allocate 10 WETH

        uint256 initialUSDCBalance = usdc.balanceOf(address(this));
        console.log("USDC balance before swap", initialUSDCBalance);

        // Call function to swap WETH to USDC and transfer to owner
        feeManager._swapWETHToUSDCAndTransfer(5e18); // Swap 5 WETH to USDC
        // feeManager.checkAndTransfer();

        // Check USDC balance after swap
        uint256 usdcBalanceAfter = usdc.balanceOf(address(this));
        assertGt(usdcBalanceAfter, initialUSDCBalance, "USDC balance did not increase after swap");
        // console.log("USDC Differenc: ", in);

        // Log the output for verification
        console.log("USDC balance after swap: ", usdcBalanceAfter);
    }

    function testDistributeWETHToPools() public {
        // Simulate WETH allocation to FeeManager
        deal(wethAddress, address(feeManager), 10e18); // Allocate 10 WETH

        // Distribute WETH to staking pools
        // feeManager._distributeWETHToPools(5e18); // Distribute 5 WETH
        feeManager.checkAndTransfer();

        // Check WETH balance after distribution
        uint256 remainingWETHBalance = weth.balanceOf(address(feeManager));
        assertLt(remainingWETHBalance, 10e18, "WETH balance should be reduced after distribution");

        // Log the output for verification
        console.log("Remaining WETH balance: ", remainingWETHBalance);
    }

    function addLiquidityToAllPools() internal {
        for (uint256 i = 0; i < indexTokens.length; i++) {
            addLiquidity(indexTokens[i]);
        }

        // addLiquidity(IERC20(rewardToken1Address)); // Example amounts

        // Add liquidity for LINK/WETH pair
        // addLiquidity(IERC20(rewardToken1Address)); // Example amounts

        // Add liquidity for WETH/USDC pair
        addLiquidity(IERC20(usdc));
    }

    function addLiquidity(IERC20 indexToken) internal {
        // Wrap ETH into WETH
        wrapEthToWeth();

        // Log balances before adding liquidity
        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 indexTokenBalance = indexToken.balanceOf(address(this));
        console.log("WETH balance before liquidity: ", wethBalance);
        console.log("IndexToken balance before liquidity: ", indexTokenBalance);

        // Check if balances are sufficient
        // address token1 = address(weth);

        require(wethBalance >= 5e18, "Not enough WETH for liquidity");
        require(indexTokenBalance >= 1000e18, "Not enough index tokens for liquidity");

        // Add liquidity
        console.log("Adding liquidity...");
        address token0 = address(weth) < address(indexToken) ? address(weth) : address(indexToken);
        address token1 = address(weth) > address(indexToken) ? address(weth) : address(indexToken);

        console.log("Token0: ", token0);
        console.log("Token1: ", token1);

        // Encode initial price: Assuming 1 WETH = 1000 index tokens
        uint160 initialPrice = encodePriceSqrt(100, 1);
        console.log("Initial price sqrt: ", uint256(initialPrice));

        address pool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, 3000);

        if (pool == address(0)) {
            console.log("Pool does not exist, creating and initializing pool");

            // Create and initialize the pool if it doesn't exist
            INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
                token0,
                token1,
                3000, // Fee tier
                initialPrice // Assuming 1 WETH = 1000 index tokens
            );
        } else {
            console.log("Pool already exists: ", pool);
        }

        IERC20(token0).approve(address(nonfungiblePositionManager), type(uint256).max);
        IERC20(token1).approve(address(nonfungiblePositionManager), type(uint256).max);
        // weth.approve(address(nonfungiblePositionManager), type(uint256).max);
        // indexToken.approve(address(nonfungiblePositionManager), type(uint256).max);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 3000, // Pool fee of 0.3%
            tickLower: getMinTick(3000), // Min tick for liquidity range
            tickUpper: getMaxTick(3000), // Max tick for liquidity range
            amount0Desired: 100e18, // 1000 index tokens
            amount1Desired: 5e18, // 5 WETH
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 1200 // Deadline of 20 minutes
        });

        (, uint128 liquidity,,) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
        console.log("Liquidity added for Index Token ", address(indexToken));
        console.log("Liquidity amount: ", liquidity);
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
