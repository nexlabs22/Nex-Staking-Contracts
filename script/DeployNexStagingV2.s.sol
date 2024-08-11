// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {NexStagingV2} from "../contracts/NexStagingV2.sol";

contract DeployNexStagingV2 is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // Use the correct addresses
        address proxyAdminAddress = 0x2E5fE2088a1d898B555e4815c176752f0Aa75421; // Your ProxyAdmin address
        address proxyAddress = 0xcA93886855021D96E7f80340C1Db182DEFBFE184; // Your TransparentUpgradeableProxy address

        // Initialize the ProxyAdmin instance with the correct address
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // Ensure the correct owner is used
        address owner = proxyAdmin.owner();
        console.log("ProxyAdmin owner is:", owner);

        // Deploy the new implementation of NexStagingV2
        NexStagingV2 newImplementation = new NexStagingV2();

        // Upgrade the proxy to use the new implementation
        try proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(proxyAddress)), address(newImplementation), ""
        ) {
            console.log("Upgrade successful");
        } catch Error(string memory reason) {
            console.log("Upgrade failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Upgrade failed with low-level error:", string(lowLevelData));
        }

        vm.stopBroadcast();

        console.log("Proxy upgraded to NexStagingV2 at:", address(newImplementation));
    }
}
