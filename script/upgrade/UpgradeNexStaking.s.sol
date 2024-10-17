// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {NexStaking} from "../contracts/NexStaking.sol";

contract UpgradeNexStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Addresses from environment variables
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address nexStakingProxyAddress = vm.envAddress("NEX_STAKING_PROXY_ADDRESS");

        // Deploy the new implementation
        NexStaking newNexStakingImplementation = new NexStaking();
        console.log("New NexStaking implementation deployed at:", address(newNexStakingImplementation));

        // Upgrade the proxy to point to the new implementation
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(nexStakingProxyAddress)), address(newNexStakingImplementation)
        );

        console.log("NexStaking proxy upgraded to new implementation at:", address(newNexStakingImplementation));

        vm.stopBroadcast();
    }
}
