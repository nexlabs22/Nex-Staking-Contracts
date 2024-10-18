// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "../../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {NexStaking} from "../../contracts/NexStaking.sol";

contract UpgradeNexStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address proxyAdminAddress = vm.envAddress("NEX_STAKING_PROXY_ADMIN_ADDRESS");
        address nexStakingProxyAddress = vm.envAddress("NEX_STAKING_PROXY_ADDRESS");

        NexStaking newNexStakingImplementation = new NexStaking();
        console.log("New NexStaking implementation deployed at:", address(newNexStakingImplementation));

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(nexStakingProxyAddress)), address(newNexStakingImplementation)
        );

        console.log("NexStaking proxy upgraded to new implementation at:", address(newNexStakingImplementation));

        vm.stopBroadcast();
    }
}
