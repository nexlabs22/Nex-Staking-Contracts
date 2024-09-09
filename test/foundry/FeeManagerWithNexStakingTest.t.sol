// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import "forge-std/Test.sol";
// import "../../contracts/FeeManager.sol";
// import "../../contracts/NexStaking.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "../../contracts/uniswap/INonfungiblePositionManager.sol";
// import "./mocks/MockERC20.sol";
// import "../../contracts/factory/ERC4626Factory.sol";
// import "../../contracts/interfaces/IUniswapV2Router02.sol";
// import "../../contracts/interfaces/IUniswapV3Factory2.sol";
// import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// contract FeeManagerWithNexStakingTest is Test {
//     using SafeERC20 for IERC20;

//     uint256 mainnetFork;

//     FeeManager feeManager;
//     NexStaking nexStaking;
//     MockERC20 nexLabsToken;
//     ERC4626Factory public erc4626Factory;

//     address user = address(1);

//     IERC20 weth;
//     IERC20 usdc;

//     IERC20[] indexTokens;
//     IERC20[] rewardTokens;

//     int24 private constant MIN_TICK = -887272;
//     int24 private constant MAX_TICK = -MIN_TICK;
//     int24 private constant TICK_SPACING = 24;

//     address uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
//     address unsiwapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
//     address unsiwapV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
//     address uniswapV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
//     INonfungiblePositionManager nonfungiblePositionManager =
//         INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
//     IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(uniswapV3FactoryAddress);

//     address owner;

//     string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

//     function setUp() public {
//         mainnetFork = vm.createFork(MAINNET_RPC_URL);
//         vm.selectFork(mainnetFork);
//         deal(address(this), 100 ether);

//         erc4626Factory = new ERC4626Factory();

//         // uint8;
//         // swapVersions[0] = 3;

//         deployTokens();

//         weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
//         usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

//         nexStaking = new NexStaking();

//         nexStaking.initialize(
//             address(nexLabsToken),
//             addressArray(indexTokens),
//             addressArray(rewardTokens),
//             new uint8[](indexTokens.length),
//             address(erc4626Factory),
//             uniswapV3Router,
//             address(weth),
//             3
//         );

//         feeManager = new FeeManager();

//         feeManager.initialize(
//             nexStaking,
//             addressArray(indexTokens),
//             addressArray(rewardTokens),
//             swapVersions,
//             uniswapV3Router,
//             unsiwapV2Router,
//             address(weth),
//             address(usdc),
//             1
//         );

//         addLiquidityToAllPools();
//     }

//     function deployTokens() internal {
//         nexLabsToken = new MockERC20("NexLabs Token", "NEX", 18);
//         nexLabsToken.mint(address(this), 1e24);

//         for (uint256 i = 0; i < 3; i++) {
//             MockERC20 indexToken = new MockERC20(
//                 string(abi.encodePacked("Index Token ", uint8(i + 1))),
//                 string(abi.encodePacked("IDX", uint8(i + 1))),
//                 18
//             );
//             indexTokens.push(indexToken);

//             indexToken.mint(user, 1000e18);
//             indexToken.mint(address(this), 1e24);

//             MockERC20 rewardToken = new MockERC20(
//                 string(abi.encodePacked("Reward Token ", uint8(i + 1))),
//                 string(abi.encodePacked("RWD", uint8(i + 1))),
//                 18
//             );
//             rewardTokens.push(rewardToken);

//             rewardToken.mint(address(this), 1e24);
//         }
//     }

//     function addLiquidityToAllPools() internal {
//         for (uint256 i = 0; i < indexTokens.length; i++) {
//             addLiquidity(indexTokens[i]);
//         }
//     }

//     function addLiquidity(IERC20 indexToken) internal {
//         wrapEthToWeth();

//         uint256 wethBalance = weth.balanceOf(address(this));
//         uint256 indexTokenBalance = indexToken.balanceOf(address(this));

//         require(wethBalance >= 5e18, "Not enough WETH");
//         require(indexTokenBalance >= 1000e18, "Not enough index tokens");

//         address token0 = address(weth) < address(indexToken) ? address(weth) : address(indexToken);
//         address token1 = address(weth) > address(indexToken) ? address(weth) : address(indexToken);

//         uint160 initialPrice = encodePriceSqrt(1000, 1);

//         address pool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, 3000);

//         if (pool == address(0)) {
//             INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
//                 token0, token1, 3000, initialPrice
//             );
//         }

//         weth.approve(address(nonfungiblePositionManager), type(uint256).max);
//         indexToken.approve(address(nonfungiblePositionManager), type(uint256).max);

//         INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
//             token0: token0,
//             token1: token1,
//             fee: 3000,
//             tickLower: getMinTick(3000),
//             tickUpper: getMaxTick(3000),
//             amount0Desired: 1000e18,
//             amount1Desired: 5e18,
//             amount0Min: 0,
//             amount1Min: 0,
//             recipient: address(this),
//             deadline: block.timestamp + 1200
//         });

//         INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
//     }

//     function wrapEthToWeth() public {
//         IWETH9 wethContract = IWETH9(address(weth));
//         wethContract.deposit{value: 10 ether}();
//     }

//     function testStakeTokensInNexStaking() public {
//         address vault = nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]));

//         indexTokens[0].approve(address(nexStaking), 1000e18);

//         vm.startPrank(user);
//         indexTokens[0].approve(vault, 1000e18);
//         nexStaking.stake(address(indexTokens[0]), 500e18);
//         vm.stopPrank();
//         assertGt(nexStaking.getUserShares(address(this), address(indexTokens[0])), 0, "Staking failed");
//     }

//     function testUnstakeTokensFromNexStaking() public {
//         deal(address(indexTokens[0]), address(this), 1000e18);
//         indexTokens[0].approve(address(nexStaking), 1000e18);

//         address vault = nexStaking.tokenAddressToVaultAddress(address(indexTokens[0]));

//         indexTokens[0].approve(vault, 1000e18);

//         nexStaking.stake(address(indexTokens[0]), 500e18);

//         nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), 250e18);
//         assertEq(indexTokens[0].balanceOf(address(this)), 250e18, "Unstaking failed");
//     }

//     function testSwapRewardTokensToWETH() public {
//         for (uint256 i = 0; i < rewardTokens.length; i++) {
//             deal(address(rewardTokens[i]), address(feeManager), 1000e18);
//         }

//         feeManager.checkAndTransfer();

//         uint256 wethBalanceAfter = weth.balanceOf(address(feeManager));
//         assertGt(wethBalanceAfter, 0, "WETH balance should increase after swaps");
//     }

//     function addressArray(IERC20[] memory tokens) internal pure returns (address[] memory) {
//         address[] memory addresses = new address[](tokens.length);
//         for (uint256 i = 0; i < tokens.length; i++) {
//             addresses[i] = address(tokens[i]);
//         }
//         return addresses;
//     }

//     function encodePriceSqrt(uint256 reserve1, uint256 reserve0) public pure returns (uint160) {
//         return uint160(sqrt((reserve1 * (2 ** 192)) / reserve0));
//     }

//     function sqrt(uint256 y) public pure returns (uint256 z) {
//         if (y > 3) {
//             z = y;
//             uint256 x = y / 2 + 1;
//             while (x < z) {
//                 z = x;
//                 x = (y / x + x) / 2;
//             }
//         } else if (y != 0) {
//             z = 1;
//         }
//     }

//     function getMinTick(int24 tickSpacing) public pure returns (int24) {
//         return int24((int256(-887272) / int256(tickSpacing) + 1) * int256(tickSpacing));
//     }

//     function getMaxTick(int24 tickSpacing) public pure returns (int24) {
//         return int24((int256(887272) / int256(tickSpacing)) * int256(tickSpacing));
//     }
// }
