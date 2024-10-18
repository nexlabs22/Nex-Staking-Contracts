// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {NexStaking} from "../contracts/NexStaking.sol";

contract DeployNexStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address[] memory indexTokensAddresses = getIndexTokens();
        address[] memory rewardTokensAddresses = getRewardTokens();
        uint8[] memory swapVersions = getSwapVersions();
        address erc4626Factory = vm.envAddress("TESTNET_ERC4626_FACTORY");
        address uniswapV3Router = vm.envAddress("TESTNET_UNISWAP_V3_ROUTER");
        address weth = vm.envAddress("TESTNET_WETH");
        uint8 feePercent = uint8(vm.envUint("FEE_PERCENT"));

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        NexStaking nexStakingImplementation = new NexStaking();

        bytes memory data = abi.encodeWithSignature(
            "initialize(address[],address[],uint8[],address,address,address,uint8)",
            indexTokensAddresses,
            rewardTokensAddresses,
            swapVersions,
            erc4626Factory,
            uniswapV3Router,
            weth,
            feePercent
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(nexStakingImplementation), address(proxyAdmin), data);

        console.log("NexStaking implementation deployed at:", address(nexStakingImplementation));
        console.log("NexStaking proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for NexStaking deployed at:", address(proxyAdmin));

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
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = 0xE8888fE3Bde6f287BDd0922bEA6E0bF6e5f418e7; // TETHER
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
