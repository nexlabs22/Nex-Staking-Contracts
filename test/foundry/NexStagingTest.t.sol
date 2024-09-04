// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {ERC4626Factory} from "../../contracts/factory/ERC4626Factory.sol";
import {NexStaking} from "../../contracts/NexStaking.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract NexStakingTest is Test {
    uint256 mainnetFork;

    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    NexStaking public nexStaking;
    IERC20 public testToken;
    ERC4626Factory public erc4626Factory;
    MockERC20 public nexLabsToken;
    MockERC20 public indexTokens1;
    MockERC20 public indexTokens2;

    address public owner = address(10); // Simulate owner account
    address public user = address(1); // Mock user
    uint256 public initialStakeAmount = 1000e18;
    uint256 public contractInitialBalance = initialStakeAmount * 100;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);

        nexLabsToken = new MockERC20("Nex Labs Token", "NXL");
        indexTokens1 = new MockERC20("Index Token 1", "ITK1");
        indexTokens2 = new MockERC20("Reward Token", "RTK");

        // Deploy mock ERC4626 factory
        erc4626Factory = new ERC4626Factory(); // Assume ERC4626Factory implementation

        // Dynamic arrays for index tokens, reward tokens, and swap versions
        address[] memory indexTokens = new address[](1);
        indexTokens[0] = address(indexTokens1);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(indexTokens2);

        uint8[] memory swapVersions = new uint8[](1);
        swapVersions[0] = 3;

        uint8 feePercent = 3;

        NexStaking nexStakingImplementation = new NexStaking();
        vm.startPrank(owner);

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address[],address[],uint8[],address,address,address,uint8)",
            address(nexLabsToken), // NexLabs token
            indexTokens, // Index tokens array
            rewardTokens, // Reward tokens array
            swapVersions, // Swap versions
            address(erc4626Factory), // ERC4626Factory address
            address(0xE592427A0AEce92De3Edee1F18E0157C05861564), // Uniswap V3 router
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // WETH address
            feePercent // Fee percent
        );

        proxyAdmin = new ProxyAdmin(owner);

        // Deploy the TransparentUpgradeableProxy pointing to NexStaking
        vm.stopPrank();
        proxy = new TransparentUpgradeableProxy(address(nexStakingImplementation), address(proxyAdmin), data);

        // Cast the proxy address to NexStaking to interact with the proxy
        nexStaking = NexStaking(address(proxy));

        // Transfer ownership of ERC4626Factory to the NexStaking contract
        // vm.prank(owner); // Simulate the owner account making this call
        // erc4626Factory.transferOwnership(address(nexStaking));

        mintAndApproveTokens(user);

        console.log("Owner address: ", owner);
    }

    function mintAndApproveTokens(address _user) internal {
        // Mint tokens to the user and the staking contract
        nexLabsToken.mint(_user, initialStakeAmount);
        indexTokens1.mint(_user, initialStakeAmount);
        indexTokens2.mint(_user, initialStakeAmount);

        nexLabsToken.mint(address(nexStaking), contractInitialBalance);
        indexTokens1.mint(address(nexStaking), contractInitialBalance);
        indexTokens2.mint(address(nexStaking), contractInitialBalance);

        // Approve tokens for the NexStaking contract
        vm.startPrank(_user);

        // Check the user's balance
        console.log("User indexTokens1 balance before approval:", indexTokens1.balanceOf(_user));

        nexLabsToken.approve(address(nexStaking), initialStakeAmount);
        indexTokens1.approve(address(nexStaking), initialStakeAmount);
        indexTokens2.approve(address(nexStaking), initialStakeAmount);

        // Check the user's allowance for indexTokens1
        uint256 allowance = indexTokens1.allowance(_user, address(nexStaking));
        console.log("Allowance for indexTokens1:", allowance);

        vm.stopPrank();
    }

    function testStake() public {
        // Check user's balance before staking
        uint256 userBalanceBefore = indexTokens1.balanceOf(user);
        console.log("User's balance before staking:", userBalanceBefore);

        // Check the user's allowance for staking
        uint256 allowanceBefore = indexTokens1.allowance(user, address(nexStaking));
        console.log("User's allowance before staking:", allowanceBefore);

        // Start staking process
        vm.startPrank(user);
        nexStaking.stake(address(indexTokens1), initialStakeAmount);
        vm.stopPrank();

        // Check user's balance after staking
        uint256 userBalanceAfter = indexTokens1.balanceOf(user);
        console.log("User's balance after staking:", userBalanceAfter);

        // Check the balance in the vault after staking
        address vault = nexStaking.tokenAddressToVaultAddress(address(indexTokens1));
        uint256 vaultBalance = indexTokens1.balanceOf(vault);
        assertEq(vaultBalance, initialStakeAmount, "Incorrect vault balance after staking");

        // Check user's position after staking
        (address owner,,, uint256 userStakeAmount,) = nexStaking._positions(user, address(indexTokens1));
        assertEq(userStakeAmount, initialStakeAmount, "Stake amount does not match the staked tokens");

        console.log("Owner", owner);
        console.log("Index Token 1", address(indexTokens1));
        console.log("Index Token 2", address(indexTokens2));
        // Assert shares received
        uint256 userShares = ERC4626(vault).balanceOf(user);
        assertGt(userShares, 0, "User did not receive shares after staking");
    }
}
