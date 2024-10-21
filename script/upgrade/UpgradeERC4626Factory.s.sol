// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "../../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC4626Factory} from "../../contracts/factory/ERC4626Factory.sol";

contract UpgradeERC4626Factory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address proxyAdminAddress = vm.envAddress("ERC4626_FACTORY_PROXY_ADMIN_ADDRESS");
        address erc4626FactoryProxyAddress = vm.envAddress("ERC4626_FACTORY_PROXY_ADDRESS");

        ERC4626Factory newERC4626FactoryImplementation = new ERC4626Factory();
        console.log("New ERC4626Factory implementation deployed at:", address(newERC4626FactoryImplementation));

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(erc4626FactoryProxyAddress)), address(newERC4626FactoryImplementation)
        );

        console.log("ERC4626Factory proxy upgraded to new implementation at:", address(newERC4626FactoryImplementation));

        vm.stopBroadcast();
    }
}
