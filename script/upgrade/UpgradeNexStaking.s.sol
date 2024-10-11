// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {NexStaking} from "../../contracts/NexStaking.sol";

contract UpgradeNexStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address proxyAdminAddress = vm.envAddress("TESTNET_PROXY_ADMIN_ADDRESS");
        address proxyAddress = vm.envAddress("TESTNET_PROXY_ADDRESS");

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        console.log("Sender Address: ", msg.sender);
        console.log("Proxy Owner: ", proxyAdmin.owner());
        require(proxyAdmin.owner() == msg.sender, "Caller is not the owner of ProxyAdmin");

        // Deploy the new implementation
        NexStaking nexStakingNewImplementation = new NexStaking();
        console.log("New NexStaking implementation deployed at:", address(nexStakingNewImplementation));

        // Prepare empty data parameter
        bytes memory data = "";

        // Perform the upgrade without initialization
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(proxyAddress)), address(nexStakingNewImplementation), data
        );

        console.log(
            "Proxy at", proxyAddress, "has been upgraded to new implementation at", address(nexStakingNewImplementation)
        );

        vm.stopBroadcast();
    }
}
