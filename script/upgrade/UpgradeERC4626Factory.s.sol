// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ERC4626Factory} from "../contracts/factory/ERC4626Factory.sol";

contract UpgradeERC4626Factory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Addresses from environment variables
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address erc4626FactoryProxyAddress = vm.envAddress("ERC4626_FACTORY_PROXY_ADDRESS");

        // Deploy the new implementation
        ERC4626Factory newERC4626FactoryImplementation = new ERC4626Factory();
        console.log("New ERC4626Factory implementation deployed at:", address(newERC4626FactoryImplementation));

        // Upgrade the proxy to point to the new implementation
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(erc4626FactoryProxyAddress)), address(newERC4626FactoryImplementation)
        );

        console.log("ERC4626Factory proxy upgraded to new implementation at:", address(newERC4626FactoryImplementation));

        vm.stopBroadcast();
    }
}
