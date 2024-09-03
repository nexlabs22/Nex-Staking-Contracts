// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Test} from "forge-std/Test.sol";
// import {NexStaking} from "../../contracts/NexStaking.sol";
// import {ERC4626Factory} from "../../contracts/factory/ERC4626Factory.sol";
// import {MockERC20} from "./mocks/MockERC20.sol";
// import {IWETH9} from "../../contracts/interfaces/IWETH9.sol";

// contract NexStakingTest is Test {
//     NexStaking nexStaking;
//     ERC4626Factory erc4626Factory;
//     MockERC20 mockToken;
//     MockERC20 mockRewardToken;
//     IWETH9 mockWeth;
//     address owner = address(this);

//     function setUp() public {
//         erc4626Factory = new ERC4626Factory();
//         mockToken = new MockERC20("Mock Token", "MTK", 18);
//         mockRewardToken = new MockERC20("Reward Token", "RTK", 18);
//         mockWeth = IWETH9(address(new MockERC20("Wrapped Ether", "WETH", 18)));

//         // Initialize tokenAddresses array
//         address[] memory tokenAddresses;
//         tokenAddresses = new address[](1);
//         tokenAddresses[0] = address(mockToken);

//         // Initialize indexTokens array
//         address[] memory indexTokens;
//         indexTokens = new address[](1);
//         indexTokens[0] = address(mockToken);

//         // Deploy the NexStaking contract with constructor
//         nexStaking = new NexStaking(
//             address(mockToken),
//             tokenAddresses,
//             indexTokens,
//             100, // Fee percent (1%)
//             address(erc4626Factory),
//             0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E, // UniswapV3Router
//             0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E, // UniswapV2Router
//             0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3, // Quoter
//             0x0227628f3F023bb0B980b67D528571c95c6DaC1c, // UniswapV3Factory
//             address(mockWeth)
//         );
//     }

//     // Test contract deployment and constructor initialization
//     function testConstructor() public {
//         assertEq(address(nexStaking.nexLabsToken()), address(mockToken));
//         assertEq(nexStaking.feePercent(), 100);
//     }

//     // Test staking with valid inputs
//     function testStake() public {
//         uint256 stakeAmount = 1e18;

//         mockToken.mint(address(this), stakeAmount);
//         mockToken.approve(address(nexStaking), stakeAmount);

//         uint256 positionId = nexStaking.stake(address(mockToken), stakeAmount);

//         (address owner,, address vault, uint256 stakedAmount, uint256 shares,) = nexStaking.getPositions(positionId);

//         assertEq(owner, address(this));
//         assertEq(stakedAmount, stakeAmount - (stakeAmount / 100)); // Account for fee
//         assertEq(shares > 0, true);
//     }

//     // Test staking with zero amount (should fail)
//     function testStakeWithZeroAmount() public {
//         vm.expectRevert("Staking amount must be greater than zero.");
//         nexStaking.stake(address(mockToken), 0);
//     }

//     // Test staking with unsupported token (should fail)
//     function testStakeWithUnsupportedToken() public {
//         MockERC20 unsupportedToken = new MockERC20("Unsupported Token", "UTK", 18);

//         vm.expectRevert("Token not supported for staking.");
//         nexStaking.stake(address(unsupportedToken), 1e18);
//     }

//     // Test unstaking with valid parameters
//     function testUnstake() public {
//         uint256 stakeAmount = 1e18;

//         mockToken.mint(address(this), stakeAmount);
//         mockToken.approve(address(nexStaking), stakeAmount);

//         uint256 positionId = nexStaking.stake(address(mockToken), stakeAmount);

//         uint256 balanceBefore = mockToken.balanceOf(address(this));
//         nexStaking.unstake(positionId, address(mockToken));
//         uint256 balanceAfter = mockToken.balanceOf(address(this));

//         assertGt(balanceAfter, balanceBefore);
//     }

//     // Test unstaking by non-owner (should fail)
//     function testUnstakeByNonOwner() public {
//         uint256 stakeAmount = 1e18;

//         mockToken.mint(address(this), stakeAmount);
//         mockToken.approve(address(nexStaking), stakeAmount);

//         uint256 positionId = nexStaking.stake(address(mockToken), stakeAmount);

//         vm.prank(address(0x123));
//         vm.expectRevert("You are not the owner of this position.");
//         nexStaking.unstake(positionId, address(mockToken));
//     }

//     // Test rewards distribution when WETH balance is above threshold
//     function testDistributeRewards() public {
//         uint256 wethAmount = 1e18;
//         mockWeth.deposit{value: wethAmount}();
//         mockWeth.transfer(address(nexStaking), wethAmount);

//         address[] memory tokens;
//         tokens = new address[](1);
//         tokens[0] = address(mockToken);

//         nexStaking.distributeRewards(tokens);
//         // Further assertions can be made on the rewards distributed
//     }

//     // Test calculateWeightOfPools with non-zero total staked amounts
//     function testCalculateWeightOfPools() public {
//         uint256 stakeAmount1 = 1e18;
//         uint256 stakeAmount2 = 2e18;

//         mockToken.mint(address(this), stakeAmount1 + stakeAmount2);
//         mockToken.approve(address(nexStaking), stakeAmount1 + stakeAmount2);

//         nexStaking.stake(address(mockToken), stakeAmount1);
//         nexStaking.stake(address(mockToken), stakeAmount2);

//         uint256[] memory weights = nexStaking.calculateWeightOfPools();
//         assertEq(weights[0] > 0, true);
//     }

//     // Test getExactAmountOut
//     function testGetExactAmountOut() public {
//         uint256 amountIn = 1e18;
//         uint256 amountOut = nexStaking.getExactAmountOut(address(mockToken), address(mockWeth), amountIn, 3);

//         assertGt(amountOut, 0);
//     }

//     // Test getAmountOut
//     function testGetAmountOut() public {
//         uint256 amountIn = 1e18;
//         uint256 amountOut = nexStaking.getAmountOut(address(mockToken), address(mockWeth), amountIn, 3);

//         assertGt(amountOut, 0);
//     }

//     // Test getPortfolioBalance
//     function testGetPortfolioBalance() public {
//         uint256 balance = nexStaking.getPortfolioBalance();
//         assertEq(balance, 0); // Initially, no staked tokens, so balance should be zero
//     }

//     receive() external payable {}
// }
