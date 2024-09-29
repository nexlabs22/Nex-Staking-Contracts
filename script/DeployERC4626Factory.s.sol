// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/factory/ERC4626Factory.sol";

contract DeployERC4626Factory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        ERC4626Factory factory = new ERC4626Factory();

        factory.initialize();

        console.log("ERC4626Factory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
