// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "../../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FeeManager} from "../../contracts/FeeManager.sol";

contract UpgradeFeeManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address proxyAdminAddress = vm.envAddress("FEE_MANAGER_PROXY_ADMIN_ADDRESS");
        address feeManagerProxyAddress = vm.envAddress("FEE_MANAGER_PROXY_ADDRESS");

        FeeManager newFeeManagerImplementation = new FeeManager();
        console.log("New FeeManager implementation deployed at:", address(newFeeManagerImplementation));

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(feeManagerProxyAddress)), address(newFeeManagerImplementation)
        );

        console.log("FeeManager proxy upgraded to new implementation at:", address(newFeeManagerImplementation));

        vm.stopBroadcast();
    }
}
