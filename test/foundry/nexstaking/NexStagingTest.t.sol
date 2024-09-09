// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Test} from "forge-std/Test.sol";
// import {console} from "forge-std/console.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
// import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// import {ERC4626Factory} from "../../../contracts/factory/ERC4626Factory.sol";
// import {NexStaking} from "../../../contracts/NexStaking.sol";
// import {FeeManager} from "../../../contracts/FeeManager.sol";
// import {MockERC20} from "./../mocks/MockERC20.sol";

// contract NexStakingTest is Test {
//     uint256 mainnetFork;

//     TransparentUpgradeableProxy public proxy;
//     ProxyAdmin public proxyAdmin;

//     NexStaking public nexStaking;
//     FeeManager public feeManager;
//     ERC4626Factory public erc4626Factory;

//     MockERC20 indexToken1;
//     MockERC20 indexToken2;
//     MockERC20 rewardToken1;
//     MockERC20 rewardToken2;
//     MockERC20 weth;
//     MockERC20 usdc;

//     address user = address(1);
//     address owner = address(10);
//     uint256 public initialStakeAmount = 1000e18;
//     uint256 public contractInitialBalance = initialStakeAmount * 100;

//     string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

//     function setUp() public {
//         mainnetFork = vm.createFork(MAINNET_RPC_URL);

//         // Deploy mock tokens and WETH
//         indexToken1 = new MockERC20("Staking Token 1", "STK1", 18);
//         indexToken2 = new MockERC20("Staking Token 2", "STK2", 18);
//         rewardToken1 = new MockERC20("Reward Token 1", "RWD1", 18);
//         rewardToken2 = new MockERC20("Reward Token 2", "RWD2", 18);
//         weth = new MockERC20("Wrapped ETH", "WETH", 18);
//         usdc = new MockERC20("USD Coin", "USDC", 6);

//         // Deploy ERC4626Factory
//         erc4626Factory = new ERC4626Factory();

//         address[] memory indexTokens = new address[](2);
//         indexTokens[0] = address(indexToken1);
//         indexTokens[1] = address(indexToken2);

//         address[] memory rewardTokens = new address[](2);
//         rewardTokens[0] = address(rewardToken1);
//         rewardTokens[1] = address(rewardToken2);

//         uint8[] memory swapVersions = new uint8[](2);
//         swapVersions[0] = 3;
//         swapVersions[0] = 2;

//         nexStaking = new NexStaking();
//         nexStaking.initialize(
//             address(indexToken1), // nexLabsTokenAddress (mocked)
//             indexTokens, // _indexTokensAddresses (empty for now)
//             rewardTokens, // _rewardTokensAddresses (empty for now)
//             swapVersions, // _swapVersions (mock for now)
//             address(erc4626Factory), // ERC4626Factory
//             0xE592427A0AEce92De3Edee1F18E0157C05861564, // UniswapV3 router (mock for now)
//             0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH (mocked)
//             3 // Fee percent
//         );

//         // Deploy FeeManager contract
//         feeManager = new FeeManager();
//         feeManager.initialize(
//             nexStaking, // nexStaking contract address
//             indexTokens, // _indexTokensAddresses (empty for now)
//             rewardTokens, // _rewardTokensAddresses (empty for now)
//             0xE592427A0AEce92De3Edee1F18E0157C05861564, // UniswapV3 router (mock for now)
//             0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // UniswapV2 router (mock for now)
//             0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH (mocked)
//             0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC (mocked)
//             1 ether // Threshold for reward distribution
//         );

//         rewardToken1.mint(address(this), 200 ether);
//         rewardToken2.mint(address(this), 100 ether);

//         rewardToken1.approve(address(feeManager), 100 ether);
//         rewardToken2.approve(address(feeManager), 50 ether);

//         rewardToken1.transfer(address(feeManager), 100 ether);
//         rewardToken2.transfer(address(feeManager), 50 ether);

//         mintAndApproveTokens(user);
//     }

//     function mintAndApproveTokens(address _user) internal {
//         // Mint and approve tokens for staking
//         indexToken1.mint(_user, initialStakeAmount);
//         indexToken2.mint(_user, initialStakeAmount);

//         indexToken1.mint(address(nexStaking), contractInitialBalance);
//         indexToken2.mint(address(nexStaking), contractInitialBalance);

//         // vm.startPrank(_user);
//         // indexToken1.approve(address(nexStaking), initialStakeAmount);
//         // indexToken2.approve(address(nexStaking), initialStakeAmount);
//         // vm.stopPrank();

//         vm.startPrank(user);
//         indexToken1.approve(address(nexStaking), type(uint256).max);
//         indexToken2.approve(address(nexStaking), type(uint256).max);
//         vm.stopPrank();
//     }

//     function testStakeAndCheckBalance() public {
//         uint256 userBalanceBefore = indexToken1.balanceOf(user);
//         console.log("User's balance before staking:", userBalanceBefore);

//         vm.startPrank(user);
//         indexToken1.approve(address(nexStaking), initialStakeAmount);
//         nexStaking.stake(address(indexToken1), initialStakeAmount);
//         vm.stopPrank();

//         uint256 userBalanceAfter = indexToken1.balanceOf(user);
//         console.log("User's balance after staking:", userBalanceAfter);

//         address vault = nexStaking.tokenAddressToVaultAddress(address(indexToken1));
//         uint256 vaultBalance = indexToken1.balanceOf(vault);
//         assertEq(vaultBalance, initialStakeAmount, "Incorrect vault balance after staking");

//         (address owner,,, uint256 userInitialStakeAmount,) = nexStaking.positions(user, address(indexToken1));
//         assertEq(userInitialStakeAmount, initialStakeAmount, "Stake amount does not match the staked tokens");

//         uint256 userShares = ERC4626(vault).balanceOf(user);
//         assertGt(userShares, 0, "User did not receive shares after staking");
//     }

//     function testSwapRewardTokensToWETH() public {
//         // Before swapping, check balances
//         assertEq(rewardToken1.balanceOf(address(feeManager)), 100 ether);
//         assertEq(rewardToken2.balanceOf(address(feeManager)), 50 ether);

//         // Mock token swaps using mocked router
//         vm.mockCall(
//             address(feeManager), abi.encodeWithSignature("swapTokens(address,address,uint256)"), abi.encode(50 ether)
//         );

//         vm.mockCall(
//             address(feeManager), abi.encodeWithSignature("swapTokens(address,address,uint256)"), abi.encode(25 ether)
//         );

//         feeManager.checkAndTransfer();

//         assertEq(weth.balanceOf(address(feeManager)), 75 ether);

//         assertEq(rewardToken1.balanceOf(address(feeManager)), 0);
//         assertEq(rewardToken2.balanceOf(address(feeManager)), 0);
//     }

//     function testCalculateWeights() public {
//         vm.mockCall(address(feeManager), abi.encodeWithSignature("getPortfolioBalance()"), abi.encode(200 ether));

//         vm.mockCall(
//             address(feeManager),
//             abi.encodeWithSignature("getAmountOut(address,address,uint256,uint8)"),
//             abi.encode(100 ether)
//         );

//         vm.mockCall(
//             address(feeManager),
//             abi.encodeWithSignature("getAmountOut(address,address,uint256,uint8)"),
//             abi.encode(100 ether)
//         );

//         uint256[] memory weights = feeManager.calculateWeightOfPools();

//         assertEq(weights[0], 1e18 / 2); // 50% for indexToken1
//         assertEq(weights[1], 1e18 / 2); // 50% for indexToken2
//     }

//     function testDistributeRewardsToVaults() public {
//         vm.mockCall(
//             address(feeManager), abi.encodeWithSignature("swapTokens(address,address,uint256)"), abi.encode(50 ether)
//         );

//         vm.mockCall(address(feeManager), abi.encodeWithSignature("getPortfolioBalance()"), abi.encode(200 ether));

//         vm.mockCall(
//             address(feeManager),
//             abi.encodeWithSignature("getAmountOut(address,address,uint256,uint8)"),
//             abi.encode(100 ether)
//         );

//         vm.mockCall(
//             address(feeManager),
//             abi.encodeWithSignature("getAmountOut(address,address,uint256,uint8)"),
//             abi.encode(100 ether)
//         );

//         vm.mockCall(
//             address(feeManager), abi.encodeWithSignature("swapTokens(address,address,uint256)"), abi.encode(25 ether)
//         );

//         vm.mockCall(
//             address(feeManager), abi.encodeWithSignature("swapTokens(address,address,uint256)"), abi.encode(25 ether)
//         );

//         feeManager.checkAndTransfer();

//         assertEq(indexToken1.balanceOf(address(erc4626Factory)), 25 ether);
//         assertEq(indexToken2.balanceOf(address(erc4626Factory)), 25 ether);
//     }
// }
