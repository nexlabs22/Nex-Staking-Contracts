// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {FeeManager} from "../contracts/FeeManager.sol";
import {NexStaking} from "../contracts/NexStaking.sol";

contract DeployFeeManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address nexStakingAddress = vm.envAddress("TESTNET_NEX_STAKING_PROXY");
        address[] memory indexTokensAddresses = getIndexTokens();
        address[] memory rewardTokensAddresses = getRewardTokens();
        uint8[] memory swapVersions = getSwapVersions();
        address uniswapRouter = vm.envAddress("TESTNET_UNISWAP_ROUTER");
        address uniswapV3Factory = vm.envAddress("TESTNET_UNISWAP_V3_FACTORY");
        address nonfungiblePositionManager = vm.envAddress("TESTNET_NONFUNGIBLE_POSITION_MANAGER");
        address erc4626Factory = vm.envAddress("TESTNET_ERC4626_FACTORY");
        address weth = vm.envAddress("TESTNET_WETH");
        address usdc = vm.envAddress("TESTNET_USDC");
        uint256 threshold = vm.envUint("THRESHOLD");

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        FeeManager feeManagerImplementation = new FeeManager();

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address[],address[],uint8[],address,address,address,address,address,uint256,address)",
            nexStakingAddress,
            indexTokensAddresses,
            rewardTokensAddresses,
            swapVersions,
            uniswapRouter,
            // uniswapV2Router,
            uniswapV3Factory,
            nonfungiblePositionManager,
            weth,
            usdc,
            threshold,
            erc4626Factory
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(feeManagerImplementation), address(proxyAdmin), data);

        console.log("FeeManager implementation deployed at:", address(feeManagerImplementation));
        console.log("FeeManager proxy deployed at:", address(proxy));
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }

    function getIndexTokens() internal pure returns (address[] memory) {
        address[] memory indexTokens = new address[](4);
        indexTokens[0] = 0x5Cd93F5C4ECE56b7faC31ABb3c1933f6a6FE7182; // ANFI
        indexTokens[1] = 0xeCBa11929312420414b6a9a70f206f90789f3069; // ARBEI
        indexTokens[2] = 0x1e881F3c8bF7A161E884B4D86Fe8810290d3095D; // MAG7
        indexTokens[3] = 0xA16FEC5964aDE6563624C16d0b2EDeC95bEEB63b; // CRYPTO5
        return indexTokens;
    }

    function getRewardTokens() internal pure returns (address[] memory) {
        address[] memory rewardTokens = new address[](5);
        rewardTokens[0] = 0x5Cd93F5C4ECE56b7faC31ABb3c1933f6a6FE7182; // ANFI
        rewardTokens[1] = 0xeCBa11929312420414b6a9a70f206f90789f3069; // ARBEI
        rewardTokens[2] = 0x1e881F3c8bF7A161E884B4D86Fe8810290d3095D; // MAG7
        rewardTokens[3] = 0xA16FEC5964aDE6563624C16d0b2EDeC95bEEB63b; // CRYPTO5
        rewardTokens[4] = 0xE8888fE3Bde6f287BDd0922bEA6E0bF6e5f418e7; // TETHER
        return rewardTokens;
    }

    function getSwapVersions() internal pure returns (uint8[] memory) {
        uint8[] memory swapVersions = new uint8[](4);
        swapVersions[0] = 3;
        swapVersions[1] = 3;
        swapVersions[2] = 3;
        swapVersions[3] = 3;
        return swapVersions;
    }
}
